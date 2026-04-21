local ml = require("moonlift")
ml.use()
local ffi = require("ffi")

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local N = getenv_num("MOONLIFT_BENCH_AUDIO_N", 48000)
local LIGHT_ITERS = getenv_num("MOONLIFT_BENCH_AUDIO_LIGHT_ITERS", 160)
local HEAVY_ITERS = getenv_num("MOONLIFT_BENCH_AUDIO_HEAVY_ITERS", 120)

local SAMPLE_RATE = 48000.0
local GAIN = 0.73
local GAIN_A = 0.65
local GAIN_B = 0.35
local ONEPOLE_A = 0.08
local ENV_ATTACK = 0.15
local ENV_RELEASE = 0.002

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

local function assert_close(name, a, b, eps)
    if math.abs(a - b) > eps then
        error(string.format("%s mismatch: %0.9f vs %0.9f (eps=%g)", name, a, b, eps), 2)
    end
end

local function assert_buf_close(name, a, b, n, eps)
    for i = 0, n - 1 do
        local av = tonumber(a[i])
        local bv = tonumber(b[i])
        if math.abs(av - bv) > eps then
            error(string.format("%s sample %d mismatch: %0.9f vs %0.9f (eps=%g)", name, i, av, bv, eps), 2)
        end
    end
end

local src_a = ffi.new("float[?]", N)
local src_b = ffi.new("float[?]", N)
local dst_lua = ffi.new("float[?]", N)
local dst_source = ffi.new("float[?]", N)
local dst_builder = ffi.new("float[?]", N)

for i = 0, N - 1 do
    local t = i / SAMPLE_RATE
    local a = 0.6 * math.sin(2.0 * math.pi * 220.0 * t)
        + 0.2 * math.sin(2.0 * math.pi * 880.0 * t)
    local b = 0.5 * math.sin(2.0 * math.pi * 110.0 * t + 0.3)
        + 0.15 * math.sin(2.0 * math.pi * 1760.0 * t)
    src_a[i] = a
    src_b[i] = b
end

local src_a_ptr = tonumber(ffi.cast("intptr_t", src_a))
local src_b_ptr = tonumber(ffi.cast("intptr_t", src_b))
local dst_lua_ptr = tonumber(ffi.cast("intptr_t", dst_lua))
local dst_source_ptr = tonumber(ffi.cast("intptr_t", dst_source))
local dst_builder_ptr = tonumber(ffi.cast("intptr_t", dst_builder))

local gain_source = code[[
func audio_gain(src: &f32, dst: &f32, n: i32, gain: f32) -> f32
    var i: i32 = 0
    var last: f32 = cast<f32>(0.0)
    while i < n do
        let y: f32 = src[i] * gain
        dst[i] = y
        last = y
        i = i + 1
    end
    return last
end
]]

local mix_source = code[[
func audio_mix2(src_a: &f32, src_b: &f32, dst: &f32, n: i32) -> f32
    var i: i32 = 0
    var last: f32 = cast<f32>(0.0)
    while i < n do
        let y: f32 = src_a[i] * cast<f32>(0.65) + src_b[i] * cast<f32>(0.35)
        dst[i] = y
        last = y
        i = i + 1
    end
    return last
end
]]

local onepole_source = code[[
func audio_onepole(src: &f32, dst: &f32, n: i32, a: f32) -> f32
    var i: i32 = 0
    var z: f32 = cast<f32>(0.0)
    while i < n do
        let x: f32 = src[i]
        z = z + a * (x - z)
        dst[i] = z
        i = i + 1
    end
    return z
end
]]

local env_source = code[[
func audio_env_follow(src: &f32, dst: &f32, n: i32) -> f32
    var i: i32 = 0
    var env: f32 = cast<f32>(0.0)
    while i < n do
        let x: f32 = src[i]
        let ax: f32 = if x < cast<f32>(0.0) then cast<f32>(0.0) - x else x end
        let coeff: f32 = if ax > env then cast<f32>(0.15) else cast<f32>(0.002) end
        env = env + coeff * (ax - env)
        dst[i] = env
        i = i + 1
    end
    return env
end
]]

local gain_builder = (func "audio_gain") {
    ptr(f32)"src",
    ptr(f32)"dst",
    i32"n",
    f32"gain",
    function(src, dst, n, gain)
        return block(function()
            local i = var(i32(0))
            local last = var(f32(0.0))
            while_(i:lt(n), function()
                local y = let(src[i] * gain)
                dst[i] = y
                last:set(y)
                i:set(i + i32(1))
            end)
            return last
        end)
    end,
}

local mix_builder = (func "audio_mix2") {
    ptr(f32)"src_a",
    ptr(f32)"src_b",
    ptr(f32)"dst",
    i32"n",
    function(src_a, src_b, dst, n)
        return block(function()
            local i = var(i32(0))
            local last = var(f32(0.0))
            while_(i:lt(n), function()
                local y = let(src_a[i] * f32(0.65) + src_b[i] * f32(0.35))
                dst[i] = y
                last:set(y)
                i:set(i + i32(1))
            end)
            return last
        end)
    end,
}

local onepole_builder = (func "audio_onepole") {
    ptr(f32)"src",
    ptr(f32)"dst",
    i32"n",
    f32"a",
    function(src, dst, n, a)
        return block(function()
            local i = var(i32(0))
            local z = var(f32(0.0))
            while_(i:lt(n), function()
                local x = let(src[i])
                z:set(z + a * (x - z))
                dst[i] = z
                i:set(i + i32(1))
            end)
            return z
        end)
    end,
}

local env_builder = (func "audio_env_follow") {
    ptr(f32)"src",
    ptr(f32)"dst",
    i32"n",
    function(src, dst, n)
        return block(function()
            local i = var(i32(0))
            local env = var(f32(0.0))
            while_(i:lt(n), function()
                local x = let(src[i])
                local ax = let((x:lt(f32(0.0)))(f32(0.0) - x, x))
                local coeff = let((ax:gt(env))(f32(0.15), f32(0.002)))
                env:set(env + coeff * (ax - env))
                dst[i] = env
                i:set(i + i32(1))
            end)
            return env
        end)
    end,
}

local gain_source_h = gain_source()
local mix_source_h = mix_source()
local onepole_source_h = onepole_source()
local env_source_h = env_source()

local gain_builder_h = gain_builder()
local mix_builder_h = mix_builder()
local onepole_builder_h = onepole_builder()
local env_builder_h = env_builder()

local function lua_gain(dst)
    local last = 0.0
    for i = 0, N - 1 do
        local y = src_a[i] * GAIN
        dst[i] = y
        last = y
    end
    return last
end

local function lua_mix(dst)
    local last = 0.0
    for i = 0, N - 1 do
        local y = src_a[i] * GAIN_A + src_b[i] * GAIN_B
        dst[i] = y
        last = y
    end
    return last
end

local function lua_onepole(dst)
    local z = 0.0
    for i = 0, N - 1 do
        local x = src_a[i]
        z = z + ONEPOLE_A * (x - z)
        dst[i] = z
    end
    return z
end

local function lua_env(dst)
    local env = 0.0
    for i = 0, N - 1 do
        local x = src_a[i]
        local ax = x < 0.0 and -x or x
        local coeff = ax > env and ENV_ATTACK or ENV_RELEASE
        env = env + coeff * (ax - env)
        dst[i] = env
    end
    return env
end

local function verify_kernel(name, lua_fn, source_fn, builder_fn, eps)
    local out_lua = lua_fn()
    local out_source = source_fn()
    local out_builder = builder_fn()
    assert_close(name .. " return source", out_lua, out_source, eps)
    assert_close(name .. " return builder", out_lua, out_builder, eps)
    assert_buf_close(name .. " buffer source", dst_lua, dst_source, N, eps)
    assert_buf_close(name .. " buffer builder", dst_lua, dst_builder, N, eps)
end

local function bench_case(name, iters, lua_fn, source_fn, builder_fn)
    verify_kernel(name, lua_fn, source_fn, builder_fn, 1e-4)
    local t_lua, out_lua = timeit(iters, lua_fn)
    local t_source, out_source = timeit(iters, source_fn)
    local t_builder, out_builder = timeit(iters, builder_fn)
    assert_close(name .. " timed source", out_lua, out_source, 1e-4)
    assert_close(name .. " timed builder", out_lua, out_builder, 1e-4)
    print(string.format(
        "%-18s lua=%8.3f ms  source=%8.3f ms  builder=%8.3f ms  src=%6.2fx  bld=%6.2fx  out=%0.6f",
        name,
        t_lua * 1000.0,
        t_source * 1000.0,
        t_builder * 1000.0,
        t_lua / t_source,
        t_lua / t_builder,
        out_lua
    ))
end

print(string.format(
    "moonlift audio bench: n=%d light_iters=%d heavy_iters=%d",
    N,
    LIGHT_ITERS,
    HEAVY_ITERS
))
print("")
print("AUDIO KERNELS")
bench_case(
    "gain",
    LIGHT_ITERS,
    function() return lua_gain(dst_lua) end,
    function() return gain_source_h(src_a_ptr, dst_source_ptr, N, GAIN) end,
    function() return gain_builder_h(src_a_ptr, dst_builder_ptr, N, GAIN) end
)
bench_case(
    "mix2",
    LIGHT_ITERS,
    function() return lua_mix(dst_lua) end,
    function() return mix_source_h(src_a_ptr, src_b_ptr, dst_source_ptr, N) end,
    function() return mix_builder_h(src_a_ptr, src_b_ptr, dst_builder_ptr, N) end
)
bench_case(
    "onepole",
    HEAVY_ITERS,
    function() return lua_onepole(dst_lua) end,
    function() return onepole_source_h(src_a_ptr, dst_source_ptr, N, ONEPOLE_A) end,
    function() return onepole_builder_h(src_a_ptr, dst_builder_ptr, N, ONEPOLE_A) end
)
bench_case(
    "env_follow",
    HEAVY_ITERS,
    function() return lua_env(dst_lua) end,
    function() return env_source_h(src_a_ptr, dst_source_ptr, N) end,
    function() return env_builder_h(src_a_ptr, dst_builder_ptr, N) end
)

local s = stats()
print("")
print(string.format(
    "compile stats: hits=%d misses=%d cache_entries=%d compiled=%d",
    s.compile_hits,
    s.compile_misses,
    s.cache_entries,
    s.compiled_functions
))
