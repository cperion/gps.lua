local ml = require("moonlift")
ml.use()
local ffi = require("ffi")

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local HOST_ITERS = getenv_num("MOONLIFT_BENCH_AGG_HOST_ITERS", 300000)
local KERNEL_N = getenv_num("MOONLIFT_BENCH_AGG_KERNEL_N", 120000)
local KERNEL_ITERS = getenv_num("MOONLIFT_BENCH_AGG_KERNEL_ITERS", 160)

local function timeit(iters, fn)
    collectgarbage()
    collectgarbage()
    local out
    local t0 = os.clock()
    for _ = 1, iters do
        out = fn()
    end
    return os.clock() - t0, out
end

local function bench_pair(name, iters, a_fn, b_fn, unit)
    a_fn()
    b_fn()
    local t_a, out_a = timeit(iters, a_fn)
    local t_b, out_b = timeit(iters, b_fn)
    assert(out_a == out_b, string.format("%s mismatch: a=%s b=%s", name, tostring(out_a), tostring(out_b)))
    local scale = unit == "ns" and 1e9 or 1e6
    local suffix = unit == "ns" and "ns" or "us"
    print(string.format(
        "%-24s A=%8.3f ms (%8.3f %s)  B=%8.3f ms (%8.3f %s)  ratio=%7.2fx  out=%s",
        name,
        t_a * 1000.0,
        t_a * scale / iters,
        suffix,
        t_b * 1000.0,
        t_b * scale / iters,
        suffix,
        t_b / t_a,
        tostring(out_a)
    ))
end

local Pair = struct_("BenchAggPair", {
    { "a", i32 },
    { "b", i32 },
})

local pair_sum_ptr = (func "bench_agg_pair_sum_ptr") {
    ptr(Pair)"p",
    function(p)
        return p.a + p.b
    end,
}

local pair_sum_byval = (func "bench_agg_pair_sum_byval") {
    Pair"p",
    function(p)
        return p.a + p.b
    end,
}

local local_scalar = (func "bench_agg_local_scalar") {
    function()
        return block(function()
            local a = let(i32(40))
            local b = let(i32(2))
            return a + b
        end)
    end,
}

local local_pair = (func "bench_agg_local_pair") {
    function()
        return block(function()
            local p = let(Pair { a = i32(40), b = i32(2) })
            return p.a + p.b
        end)
    end,
}

local scalar_var_update = (func "bench_agg_scalar_var_update") {
    i32"n",
    function(n)
        return block(function()
            local a = var(i32(0))
            local b = var(i32(0))
            local i = var(i32(0))
            while_(i:lt(n), function()
                a:set(a + i32(1))
                b:set(b + i32(2))
                i:set(i + i32(1))
            end)
            return a + b
        end)
    end,
}

local pair_var_update = (func "bench_agg_pair_var_update") {
    i32"n",
    function(n)
        return block(function()
            local p = var(Pair { a = i32(0), b = i32(0) })
            local i = var(i32(0))
            while_(i:lt(n), function()
                p:set(Pair { a = p.a + i32(1), b = p.b + i32(2) })
                i:set(i + i32(1))
            end)
            return p.a + p.b
        end)
    end,
}

local invoke_ptr = (func "bench_agg_invoke_ptr") {
    i32"n",
    ptr(Pair)"p",
    function(n, p)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, invoke(pair_sum_ptr, p)))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local invoke_byval = (func "bench_agg_invoke_byval") {
    i32"n",
    Pair"p",
    function(n, p)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, invoke(pair_sum_byval, p)))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local pair_sum_ptr_h = pair_sum_ptr()
local pair_sum_byval_h = pair_sum_byval()
local local_scalar_h = local_scalar()
local local_pair_h = local_pair()
local scalar_var_update_h = scalar_var_update()
local pair_var_update_h = pair_var_update()
local invoke_ptr_h = invoke_ptr()
local invoke_byval_h = invoke_byval()

local pair_buf = ffi.new("int32_t[2]")
pair_buf[0] = 20
pair_buf[1] = 22
local pair_ptr_addr = tonumber(ffi.cast("intptr_t", pair_buf))

print(string.format(
    "moonlift aggregate bench: host_iters=%d kernel_n=%d kernel_iters=%d",
    HOST_ITERS,
    KERNEL_N,
    KERNEL_ITERS
))
print("")
print("HOST PARAM SHAPE")
bench_pair("ptr vs byval host", HOST_ITERS, function() return pair_sum_ptr_h(pair_ptr_addr) end, function() return pair_sum_byval_h(pair_ptr_addr) end, "ns")
print("")
print("LOCAL AGGREGATES")
bench_pair("scalar vs pair let", HOST_ITERS, function() return local_scalar_h() end, function() return local_pair_h() end, "ns")
bench_pair("scalar vs pair var", KERNEL_ITERS, function() return scalar_var_update_h(KERNEL_N) end, function() return pair_var_update_h(KERNEL_N) end, "us")
print("")
print("COMPILED INVOKE SHAPE")
bench_pair("invoke ptr/byval", KERNEL_ITERS, function() return invoke_ptr_h(KERNEL_N, pair_ptr_addr) end, function() return invoke_byval_h(KERNEL_N, pair_ptr_addr) end, "us")
