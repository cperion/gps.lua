local ml = require("moonlift")
ml.use()
local ffi = require("ffi")

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local HOST_CALL_ITERS = getenv_num("MOONLIFT_BENCH_CALLS_HOST_ITERS", 500000)
local KERNEL_N = getenv_num("MOONLIFT_BENCH_CALLS_KERNEL_N", 120000)
local KERNEL_ITERS = getenv_num("MOONLIFT_BENCH_CALLS_KERNEL_ITERS", 120)
local ARRAY_N = getenv_num("MOONLIFT_BENCH_CALLS_ARRAY_N", 32768)
local ARRAY_ITERS = getenv_num("MOONLIFT_BENCH_CALLS_ARRAY_ITERS", 220)

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
        "%-22s A=%8.3f ms (%8.3f %s)  B=%8.3f ms (%8.3f %s)  ratio=%7.2fx  out=%s",
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

local function bench_speedup(name, iters, lua_fn, moonlift_fn)
    lua_fn()
    moonlift_fn()
    local t_lua, out_lua = timeit(iters, lua_fn)
    local t_ml, out_ml = timeit(iters, moonlift_fn)
    assert(out_lua == out_ml, string.format("%s mismatch: lua=%s moonlift=%s", name, tostring(out_lua), tostring(out_ml)))
    print(string.format(
        "%-22s lua=%8.3f ms  moonlift=%8.3f ms  speedup=%7.2fx  out=%s",
        name,
        t_lua * 1000.0,
        t_ml * 1000.0,
        t_lua / t_ml,
        tostring(out_lua)
    ))
end

local function bench_host_calls(name, lua_fn, moonlift_fn)
    lua_fn()
    moonlift_fn()
    local t_lua, out_lua = timeit(1, lua_fn)
    local t_ml, out_ml = timeit(1, moonlift_fn)
    assert(out_lua == out_ml, string.format("%s mismatch: lua=%s moonlift=%s", name, tostring(out_lua), tostring(out_ml)))
    print(string.format(
        "%-22s lua=%8.3f ms (%8.3f ns/call)  moonlift=%8.3f ms (%8.3f ns/call)  ratio=%7.2fx  out=%s",
        name,
        t_lua * 1000.0,
        t_lua * 1e9 / HOST_CALL_ITERS,
        t_ml * 1000.0,
        t_ml * 1e9 / HOST_CALL_ITERS,
        t_ml / t_lua,
        tostring(out_lua)
    ))
end

local inc = (func "bench_calls_inc") {
    i32"x",
    function(x)
        return x + i32(1)
    end,
}

local add2 = (func "bench_calls_add2") {
    i32"x",
    function(x)
        return x + i32(2)
    end,
}

local sum_inline = (func "bench_calls_sum_inline") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, i + i32(2)))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local sum_invoke = (func "bench_calls_sum_invoke") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, invoke(add2, i)))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

ffi.cdef[[ int abs(int x); ]]
local libc = import_module("libc", ffi.C)
local c_abs = libc:extern("abs") {
    i32"x",
    i32,
}

local abs_sum = (func "bench_calls_abs_sum") {
    ptr(i32)"arr",
    i32"n",
    function(arr, n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, invoke(c_abs, arr[i])))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local inc_h = inc()
local sum_inline_h = sum_inline()
local sum_invoke_h = sum_invoke()
local abs_sum_h = abs_sum()

local arr = ffi.new("int32_t[?]", ARRAY_N)
for i = 0, ARRAY_N - 1 do
    arr[i] = ((i * 13) % 97) - 48
end
local arr_ptr = tonumber(ffi.cast("intptr_t", arr))

local function lua_inc(x)
    return x + 1
end

local lua_holder = { fn = lua_inc }
local moonlift_holder = { fn = inc_h }

local function lua_host_inc_loop()
    local out = 0
    for i = 1, HOST_CALL_ITERS do
        out = out + lua_holder.fn(i)
    end
    return out
end

local function moonlift_host_inc_loop()
    local out = 0
    for i = 1, HOST_CALL_ITERS do
        out = out + moonlift_holder.fn(i)
    end
    return out
end

local function lua_sum_inline()
    local acc = 0
    for i = 0, KERNEL_N - 1 do
        acc = acc + (i + 2)
    end
    return acc
end

local function lua_abs_sum()
    local acc = 0
    for i = 0, ARRAY_N - 1 do
        acc = acc + ffi.C.abs(arr[i])
    end
    return acc
end

print(string.format(
    "moonlift calls bench: host_iters=%d kernel_n=%d kernel_iters=%d array_n=%d array_iters=%d",
    HOST_CALL_ITERS,
    KERNEL_N,
    KERNEL_ITERS,
    ARRAY_N,
    ARRAY_ITERS
))
print("")
print("HOST CALL OVERHEAD")
bench_host_calls("lua vs compiled call", lua_host_inc_loop, moonlift_host_inc_loop)
print("")
print("COMPILED CALL SHAPES")
bench_speedup("inline kernel", KERNEL_ITERS, lua_sum_inline, function() return sum_inline_h(KERNEL_N) end)
bench_pair("inline vs invoke", KERNEL_ITERS, function() return sum_inline_h(KERNEL_N) end, function() return sum_invoke_h(KERNEL_N) end, "us")
print("")
print("EXTERN / IMPORT")
bench_speedup("abs_sum", ARRAY_ITERS, lua_abs_sum, function() return abs_sum_h(arr_ptr, ARRAY_N) end)
