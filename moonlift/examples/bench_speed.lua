local ml = require("moonlift")
ml.use()
local ffi = require("ffi")

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local LEN = getenv_num("MOONLIFT_BENCH_LEN", 4096)
local ROUNDS = getenv_num("MOONLIFT_BENCH_ROUNDS", 64)
local ITERS = getenv_num("MOONLIFT_BENCH_ITERS", 200)
local PAIR_ITERS = getenv_num("MOONLIFT_BENCH_PAIR_ITERS", 200000)

local function bench(name, fn)
    collectgarbage()
    collectgarbage()
    local t0 = os.clock()
    local out
    for _ = 1, ITERS do
        out = fn()
    end
    local dt = os.clock() - t0
    print(string.format("%-28s %9.3f ms total %9.3f us/iter  out=%s", name, dt * 1000.0, dt * 1e6 / ITERS, tostring(out)))
    return dt, out
end

local function bench_pair(name, fn)
    collectgarbage()
    collectgarbage()
    local t0 = os.clock()
    local out
    for _ = 1, PAIR_ITERS do
        out = fn()
    end
    local dt = os.clock() - t0
    print(string.format("%-28s %9.3f ms total %9.3f ns/call out=%s", name, dt * 1000.0, dt * 1e9 / PAIR_ITERS, tostring(out)))
    return dt, out
end

local memcpy_loop = (func "bench_memcpy_loop") {
    ptr(u8)"dst",
    ptr(u8)"src",
    usize"len",
    i32"rounds",
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

local memcpy_intr = (func "bench_memcpy_intr") {
    ptr(u8)"dst",
    ptr(u8)"src",
    usize"len",
    i32"rounds",
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

local memset_loop = (func "bench_memset_loop") {
    ptr(u8)"dst",
    u8"byte_value",
    usize"len",
    i32"rounds",
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

local memset_intr = (func "bench_memset_intr") {
    ptr(u8)"dst",
    u8"byte_value",
    usize"len",
    i32"rounds",
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

local memcmp_loop = (func "bench_memcmp_loop") {
    ptr(u8)"a",
    ptr(u8)"b",
    usize"len",
    i32"rounds",
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

local memcmp_intr = (func "bench_memcmp_intr") {
    ptr(u8)"a",
    ptr(u8)"b",
    usize"len",
    i32"rounds",
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

local Pair = struct_("BenchPair", {
    { "a", i32 },
    { "b", i32 },
})

local pair_sum_ptr = (func "bench_pair_sum_ptr") {
    ptr(Pair)"p",
    function(p)
        return p.a + p.b
    end,
}

local pair_sum_byval = (func "bench_pair_sum_byval") {
    Pair"p",
    function(p)
        return p.a + p.b
    end,
}

local memcpy_loop_h = memcpy_loop()
local memcpy_intr_h = memcpy_intr()
local memset_loop_h = memset_loop()
local memset_intr_h = memset_intr()
local memcmp_loop_h = memcmp_loop()
local memcmp_intr_h = memcmp_intr()
local pair_sum_ptr_h = pair_sum_ptr()
local pair_sum_byval_h = pair_sum_byval()

local src = ffi.new("uint8_t[?]", LEN)
local dst = ffi.new("uint8_t[?]", LEN)
local eqb = ffi.new("uint8_t[?]", LEN)
for i = 0, LEN - 1 do
    local v = i % 251
    src[i] = v
    eqb[i] = v
    dst[i] = 0
end

local srcp = tonumber(ffi.cast("intptr_t", src))
local dstp = tonumber(ffi.cast("intptr_t", dst))
local eqp = tonumber(ffi.cast("intptr_t", eqb))

local pair_buf = ffi.new("int32_t[2]")
pair_buf[0] = 20
pair_buf[1] = 22
local pair_ptr = tonumber(ffi.cast("intptr_t", pair_buf))

print(string.format("moonlift bench: len=%d rounds=%d iters=%d pair_iters=%d", LEN, ROUNDS, ITERS, PAIR_ITERS))
print("")
print("MEMORY PRIMITIVES")
local t_memcpy_loop = bench("memcpy loop", function() return memcpy_loop_h(dstp, srcp, LEN, ROUNDS) end)
local t_memcpy_intr = bench("memcpy intrinsic", function() return memcpy_intr_h(dstp, srcp, LEN, ROUNDS) end)
print(string.format("%-28s %9.2fx", "memcpy speedup", t_memcpy_loop / t_memcpy_intr))
print("")
local t_memset_loop = bench("memset loop", function() return memset_loop_h(dstp, 7, LEN, ROUNDS) end)
local t_memset_intr = bench("memset intrinsic", function() return memset_intr_h(dstp, 7, LEN, ROUNDS) end)
print(string.format("%-28s %9.2fx", "memset speedup", t_memset_loop / t_memset_intr))
print("")
local t_memcmp_loop = bench("memcmp loop", function() return memcmp_loop_h(srcp, eqp, LEN, ROUNDS) end)
local t_memcmp_intr = bench("memcmp intrinsic", function() return memcmp_intr_h(srcp, eqp, LEN, ROUNDS) end)
print(string.format("%-28s %9.2fx", "memcmp speedup", t_memcmp_loop / t_memcmp_intr))
print("")
print("AGGREGATE CALL SHAPE")
local t_pair_ptr = bench_pair("pair ptr param", function() return pair_sum_ptr_h(pair_ptr) end)
local t_pair_byval = bench_pair("pair byval param", function() return pair_sum_byval_h(pair_ptr) end)
print(string.format("%-28s %9.2fx", "byval/ptr cost", t_pair_byval / t_pair_ptr))
