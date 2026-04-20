local ml = require("moonlift")
ml.use()
local ffi = require("ffi")
local bit = require("bit")

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local SCALAR_N = getenv_num("MOONLIFT_BENCH_SCALAR_N", 200000)
local ARRAY_N = getenv_num("MOONLIFT_BENCH_ARRAY_N", 32768)
local SCALAR_ITERS = getenv_num("MOONLIFT_BENCH_SCALAR_ITERS", 120)
local ARRAY_ITERS = getenv_num("MOONLIFT_BENCH_ARRAY_ITERS", 220)

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

local function bench_case(name, iters, lua_fn, moonlift_fn)
    lua_fn()
    moonlift_fn()
    local t_lua, out_lua = timeit(iters, lua_fn)
    local t_ml, out_ml = timeit(iters, moonlift_fn)
    assert(out_lua == out_ml, string.format("%s mismatch: lua=%s moonlift=%s", name, tostring(out_lua), tostring(out_ml)))
    print(string.format(
        "%-20s lua=%8.3f ms  moonlift=%8.3f ms  speedup=%7.2fx  out=%s",
        name,
        t_lua * 1000.0,
        t_ml * 1000.0,
        t_lua / t_ml,
        tostring(out_lua)
    ))
end

local affine_sum = (func "bench_affine_sum") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                local term = let(i * i32(3) + i32(7))
                acc:set(acc + sext(i64, term))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local branch_sum = (func "bench_branch_sum") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                local term = let(((i % i32(7)):lt(i32(3)))(
                    i * i32(2) + i32(1),
                    i / i32(2) - i32(3)
                ))
                acc:set(acc + sext(i64, term))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local bitmix_sum = (func "bench_bitmix_sum") {
    u32"n",
    function(n)
        return block(function()
            local i = var(u32(0))
            local acc = var(u64(0))
            while_(i:lt(n), function()
                local x = let(i * u32(1664525) + u32(1013904223))
                local y = let(x:bxor(x:shr_u(u32(13))))
                local z = let(y + y:shl(u32(7)))
                acc:set(acc + zext(u64, z:band(u32(0xffff))))
                i:set(i + u32(1))
            end)
            return acc
        end)
    end,
}

local array_sum = (func "bench_array_sum") {
    ptr(i32)"arr",
    i32"n",
    function(arr, n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, arr[i]))
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

local abs_sum = (func "bench_abs_sum") {
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

local affine_sum_h = affine_sum()
local branch_sum_h = branch_sum()
local bitmix_sum_h = bitmix_sum()
local array_sum_h = array_sum()
local abs_sum_h = abs_sum()

local arr = ffi.new("int32_t[?]", ARRAY_N)
for i = 0, ARRAY_N - 1 do
    arr[i] = ((i * 13) % 97) - 48
end
local arr_ptr = tonumber(ffi.cast("intptr_t", arr))

local function lua_affine_sum()
    local acc = 0
    for i = 0, SCALAR_N - 1 do
        acc = acc + (i * 3 + 7)
    end
    return acc
end

local function lua_branch_sum()
    local acc = 0
    for i = 0, SCALAR_N - 1 do
        local term
        if (i % 7) < 3 then
            term = i * 2 + 1
        else
            term = math.floor(i / 2) - 3
        end
        acc = acc + term
    end
    return acc
end

local function lua_bitmix_sum()
    local acc = 0
    for i = 0, SCALAR_N - 1 do
        local x = bit.tobit(i * 1664525 + 1013904223)
        local y = bit.bxor(x, bit.rshift(x, 13))
        local z = bit.tobit(y + bit.lshift(y, 7))
        acc = acc + bit.band(z, 0xffff)
    end
    return acc
end

local function lua_array_sum()
    local acc = 0
    for i = 0, ARRAY_N - 1 do
        acc = acc + arr[i]
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
    "moonlift general bench: scalar_n=%d array_n=%d scalar_iters=%d array_iters=%d",
    SCALAR_N,
    ARRAY_N,
    SCALAR_ITERS,
    ARRAY_ITERS
))
print("")
print("COMPUTE KERNELS")
bench_case("affine_sum", SCALAR_ITERS, lua_affine_sum, function() return affine_sum_h(SCALAR_N) end)
bench_case("branch_sum", SCALAR_ITERS, lua_branch_sum, function() return branch_sum_h(SCALAR_N) end)
bench_case("bitmix_sum", SCALAR_ITERS, lua_bitmix_sum, function() return bitmix_sum_h(SCALAR_N) end)
print("")
print("ARRAY / FFI KERNELS")
bench_case("array_sum", ARRAY_ITERS, lua_array_sum, function() return array_sum_h(arr_ptr, ARRAY_N) end)
bench_case("abs_sum", ARRAY_ITERS, lua_abs_sum, function() return abs_sum_h(arr_ptr, ARRAY_N) end)

local s = stats()
print("")
print(string.format(
    "compile stats: hits=%d misses=%d cache_entries=%d compiled=%d",
    s.compile_hits,
    s.compile_misses,
    s.cache_entries,
    s.compiled_functions
))
