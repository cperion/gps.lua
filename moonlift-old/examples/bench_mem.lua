local ml = require("moonlift")
ml.use()
local ffi = require("ffi")

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local LEN = getenv_num("MOONLIFT_BENCH_MEM_LEN", 4096)
local ROUNDS = getenv_num("MOONLIFT_BENCH_MEM_ROUNDS", 64)
local ITERS = getenv_num("MOONLIFT_BENCH_MEM_ITERS", 200)

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

local function bench_pair(name, a_fn, b_fn)
    a_fn()
    b_fn()
    local t_a, out_a = timeit(ITERS, a_fn)
    local t_b, out_b = timeit(ITERS, b_fn)
    assert(out_a == out_b, string.format("%s mismatch: a=%s b=%s", name, tostring(out_a), tostring(out_b)))
    print(string.format(
        "%-18s A=%8.3f ms  B=%8.3f ms  ratio=%7.2fx  out=%s",
        name,
        t_a * 1000.0,
        t_b * 1000.0,
        t_a / t_b,
        tostring(out_a)
    ))
end

local memcpy_loop = (func "bench_mem_memcpy_loop") {
    ptr(u8)"dst", ptr(u8)"src", usize"len", i32"rounds",
    function(dst, src, len, rounds)
        return block(function()
            local r = var(i32(0))
            while_(r:lt(rounds), function()
                local i = var(usize(0))
                while_(i:lt(len), function()
                    dst[i] = src[i]
                    i:set(i + usize(1))
                end)
                r:set(r + i32(1))
            end)
            return zext(i32, dst[0]) + zext(i32, dst[len - usize(1)])
        end)
    end,
}

local memcpy_intr = (func "bench_mem_memcpy_intr") {
    ptr(u8)"dst", ptr(u8)"src", usize"len", i32"rounds",
    function(dst, src, len, rounds)
        return block(function()
            local r = var(i32(0))
            while_(r:lt(rounds), function()
                memcpy(dst, src, len)
                r:set(r + i32(1))
            end)
            return zext(i32, dst[0]) + zext(i32, dst[len - usize(1)])
        end)
    end,
}

local memmove_loop = (func "bench_mem_memmove_loop") {
    ptr(u8)"dst", ptr(u8)"src", usize"len", i32"rounds",
    function(dst, src, len, rounds)
        return block(function()
            local r = var(i32(0))
            while_(r:lt(rounds), function()
                local i = var(len)
                while_(i:gt(usize(0)), function()
                    i:set(i - usize(1))
                    dst[i] = src[i]
                end)
                r:set(r + i32(1))
            end)
            return zext(i32, dst[0]) + zext(i32, dst[len - usize(1)])
        end)
    end,
}

local memmove_intr = (func "bench_mem_memmove_intr") {
    ptr(u8)"dst", ptr(u8)"src", usize"len", i32"rounds",
    function(dst, src, len, rounds)
        return block(function()
            local r = var(i32(0))
            while_(r:lt(rounds), function()
                memmove(dst, src, len)
                r:set(r + i32(1))
            end)
            return zext(i32, dst[0]) + zext(i32, dst[len - usize(1)])
        end)
    end,
}

local memset_loop = (func "bench_mem_memset_loop") {
    ptr(u8)"dst", u8"byte_value", usize"len", i32"rounds",
    function(dst, byte_value, len, rounds)
        return block(function()
            local r = var(i32(0))
            while_(r:lt(rounds), function()
                local i = var(usize(0))
                while_(i:lt(len), function()
                    dst[i] = byte_value
                    i:set(i + usize(1))
                end)
                r:set(r + i32(1))
            end)
            return zext(i32, dst[0]) + zext(i32, dst[len - usize(1)])
        end)
    end,
}

local memset_intr = (func "bench_mem_memset_intr") {
    ptr(u8)"dst", u8"byte_value", usize"len", i32"rounds",
    function(dst, byte_value, len, rounds)
        return block(function()
            local r = var(i32(0))
            while_(r:lt(rounds), function()
                memset(dst, byte_value, len)
                r:set(r + i32(1))
            end)
            return zext(i32, dst[0]) + zext(i32, dst[len - usize(1)])
        end)
    end,
}

local memcmp_loop = (func "bench_mem_memcmp_loop") {
    ptr(u8)"a", ptr(u8)"b", usize"len", i32"rounds",
    function(a, b, len, rounds)
        return block(function()
            local r = var(i32(0))
            local acc = var(i32(0))
            while_(r:lt(rounds), function()
                local i = var(usize(0))
                local out = var(i32(0))
                while_(i:lt(len), function()
                    local av = let(zext(i32, a[i]))
                    local bv = let(zext(i32, b[i]))
                    local diff = let((av:lt(bv))(i32(-1), (av:gt(bv))(i32(1), i32(0))))
                    out:set((out:eq(i32(0)))(diff, out))
                    i:set(i + usize(1))
                end)
                acc:set(acc + out)
                r:set(r + i32(1))
            end)
            return acc
        end)
    end,
}

local memcmp_intr = (func "bench_mem_memcmp_intr") {
    ptr(u8)"a", ptr(u8)"b", usize"len", i32"rounds",
    function(a, b, len, rounds)
        return block(function()
            local r = var(i32(0))
            local acc = var(i32(0))
            while_(r:lt(rounds), function()
                acc:set(acc + memcmp(a, b, len))
                r:set(r + i32(1))
            end)
            return acc
        end)
    end,
}

local memcpy_loop_h = memcpy_loop()
local memcpy_intr_h = memcpy_intr()
local memmove_loop_h = memmove_loop()
local memmove_intr_h = memmove_intr()
local memset_loop_h = memset_loop()
local memset_intr_h = memset_intr()
local memcmp_loop_h = memcmp_loop()
local memcmp_intr_h = memcmp_intr()

local src = ffi.new("uint8_t[?]", LEN + 32)
local dst = ffi.new("uint8_t[?]", LEN + 32)
local eqb = ffi.new("uint8_t[?]", LEN + 32)
for i = 0, LEN + 31 do
    local v = i % 251
    src[i] = v
    eqb[i] = v
    dst[i] = 0
end

local srcp = tonumber(ffi.cast("intptr_t", src))
local dstp = tonumber(ffi.cast("intptr_t", dst))
local ov_srcp = tonumber(ffi.cast("intptr_t", dst + 8))
local eqp = tonumber(ffi.cast("intptr_t", eqb))

print(string.format("moonlift mem bench: len=%d rounds=%d iters=%d", LEN, ROUNDS, ITERS))
print("")
bench_pair("memcpy", function() return memcpy_loop_h(dstp, srcp, LEN, ROUNDS) end, function() return memcpy_intr_h(dstp, srcp, LEN, ROUNDS) end)
bench_pair("memmove", function() return memmove_loop_h(dstp, ov_srcp, LEN, ROUNDS) end, function() return memmove_intr_h(dstp, ov_srcp, LEN, ROUNDS) end)
bench_pair("memset", function() return memset_loop_h(dstp, 7, LEN, ROUNDS) end, function() return memset_intr_h(dstp, 7, LEN, ROUNDS) end)
bench_pair("memcmp", function() return memcmp_loop_h(srcp, eqp, LEN, ROUNDS) end, function() return memcmp_intr_h(srcp, eqp, LEN, ROUNDS) end)
