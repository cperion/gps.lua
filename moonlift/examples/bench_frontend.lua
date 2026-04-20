local ml = require("moonlift")
ml.use()
local lower = ml.lower

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local BUILD_ITERS = getenv_num("MOONLIFT_BENCH_FRONTEND_BUILD_ITERS", 300)
local COMPILE_ITERS = getenv_num("MOONLIFT_BENCH_FRONTEND_COMPILE_ITERS", 40)
local CALL_ITERS = getenv_num("MOONLIFT_BENCH_FRONTEND_CALL_ITERS", 300000)
local N = getenv_num("MOONLIFT_BENCH_FRONTEND_N", 2000)

local function timeit(iters, fn)
    collectgarbage()
    collectgarbage()
    local out
    local t0 = os.clock()
    for i = 1, iters do
        out = fn(i)
    end
    return os.clock() - t0, out
end

local function avg(dt, iters)
    return dt / iters
end

local function unit_scale(unit)
    return ({ ms = 1000.0, us = 1e6, ns = 1e9 })[unit] or 1000.0
end

local function print_avg(name, unit, dt, iters, out)
    local scale = unit_scale(unit)
    print(string.format(
        "%-28s %9.3f %s/iter  out=%s",
        name,
        avg(dt, iters) * scale,
        unit,
        tostring(out)
    ))
end

local function print_pair(name, unit, a_name, a_dt, a_iters, b_name, b_dt, b_iters)
    local a = avg(a_dt, a_iters)
    local b = avg(b_dt, b_iters)
    local scale = unit_scale(unit)
    print(string.format(
        "%-28s %-10s=%9.3f %s  %-10s=%9.3f %s  ratio=%7.2fx",
        name,
        a_name,
        a * scale,
        unit,
        b_name,
        b * scale,
        unit,
        b / a
    ))
end

local function make_builder_kernel(name)
    return (func(name)) {
        i32"n",
        function(n)
            return block(function()
                local i = var(i32(0))
                local acc = var(i32(0))
                while_(i:lt(n), function()
                    local term = let(((i % i32(7)):lt(i32(3)))(i * i32(2) + i32(1), i / i32(2) - i32(3)))
                    acc:set(acc + term)
                    i:set(i + i32(1))
                end)
                return acc
            end)
        end,
    }
end

local function make_source_text(name)
    return ([=[
func %s(n: i32) -> i32
    var i: i32 = 0
    var acc: i32 = 0
    while i < n do
        let term = if i %% 7 < 3 then i * 2 + 1 else i / 2 - 3 end
        acc = acc + term
        i = i + 1
    end
    return acc
end
]=]):format(name)
end

local function make_builder_module(tag)
    local add2 = (func("bench_front_builder_add2_" .. tag)) {
        i32"x",
        function(x)
            return x + i32(2)
        end,
    }
    local mix = (func("bench_front_builder_mix_" .. tag)) {
        i32"x",
        function(x)
            return block(function()
                local y = let(add2(x))
                return y * i32(2)
            end)
        end,
    }
    return module { add2, mix }
end

local function make_source_module_text(tag)
    return ([=[
func add2_%s(x: i32) -> i32
    return x + 2
end

func mix_%s(x: i32) -> i32
    return add2_%s(x) * 2
end
]=]):format(tag, tag, tag)
end

local HOT_SOURCE_TEXT = make_source_text("bench_front_hot_source")
local HOT_SOURCE_AST = parse.code(HOT_SOURCE_TEXT)
local HOT_SOURCE_FN = lower.code(HOT_SOURCE_AST)
local HOT_SOURCE_HANDLE = HOT_SOURCE_FN()

local HOT_BUILDER_FN = make_builder_kernel("bench_front_hot_builder")
local HOT_BUILDER_HANDLE = HOT_BUILDER_FN()

assert(HOT_BUILDER_HANDLE(N) == HOT_SOURCE_HANDLE(N))

local HOT_MODULE_TEXT = make_source_module_text("hot")
local HOT_MODULE_AST = parse.module(HOT_MODULE_TEXT)
local HOT_SOURCE_MODULE = lower.module(HOT_MODULE_AST)
local HOT_SOURCE_COMPILED_MODULE = HOT_SOURCE_MODULE()
local HOT_BUILDER_MODULE = make_builder_module("hot")
local HOT_BUILDER_COMPILED_MODULE = HOT_BUILDER_MODULE()
assert(HOT_BUILDER_COMPILED_MODULE.bench_front_builder_mix_hot(19) == HOT_SOURCE_COMPILED_MODULE.mix_hot(19))

local function bench_function_build_split()
    print("FUNCTION BUILD SPLIT")
    local t_builder, builder_fn = timeit(BUILD_ITERS, function(i)
        return make_builder_kernel("bench_front_build_builder_" .. i)
    end)
    local t_parse_cold, ast_cold = timeit(BUILD_ITERS, function(i)
        return parse.code(make_source_text("bench_front_parse_cold_" .. i))
    end)
    local t_parse_hot, ast_hot = timeit(BUILD_ITERS, function()
        return parse.code(HOT_SOURCE_TEXT)
    end)
    local t_lower_only, lower_fn = timeit(BUILD_ITERS, function()
        return lower.code(HOT_SOURCE_AST)
    end)
    local t_source_cold, source_fn_cold = timeit(BUILD_ITERS, function(i)
        return code(make_source_text("bench_front_source_cold_" .. i))
    end)
    local t_source_hot, source_fn_hot = timeit(BUILD_ITERS, function()
        return code(HOT_SOURCE_TEXT)
    end)

    local sample_builder = builder_fn()
    local sample_lower = lower_fn()
    local sample_source_cold = source_fn_cold()
    local sample_source_hot = source_fn_hot()
    assert(sample_builder(N) == sample_lower(N))
    assert(sample_builder(N) == sample_source_cold(N))
    assert(sample_builder(N) == sample_source_hot(N))
    assert(ast_cold ~= nil and ast_hot ~= nil)

    print_avg("builder build", "us", t_builder, BUILD_ITERS, sample_builder(N))
    print_avg("ast parse cold", "us", t_parse_cold, BUILD_ITERS, "<ast>")
    print_avg("ast parse hot", "us", t_parse_hot, BUILD_ITERS, "<ast>")
    print_avg("lua lower only", "us", t_lower_only, BUILD_ITERS, sample_lower(N))
    print_avg("source api cold", "us", t_source_cold, BUILD_ITERS, sample_source_cold(N))
    print_avg("source api hot", "us", t_source_hot, BUILD_ITERS, sample_source_hot(N))
    print_pair("build gap cold", "us", "builder", t_builder, BUILD_ITERS, "source", t_source_cold, BUILD_ITERS)
    print_pair("build gap hot", "us", "builder", t_builder, BUILD_ITERS, "source", t_source_hot, BUILD_ITERS)
    print("")
end

local function bench_function_compile_split()
    print("FUNCTION COMPILE SPLIT")
    local t_builder_cold, builder_handle_cold = timeit(COMPILE_ITERS, function(i)
        return make_builder_kernel("bench_front_compile_builder_" .. i)()
    end)
    local t_source_cold, source_handle_cold = timeit(COMPILE_ITERS, function(i)
        return code(make_source_text("bench_front_compile_source_" .. i))()
    end)
    local t_builder_hot, builder_handle_hot = timeit(COMPILE_ITERS, function()
        return HOT_BUILDER_FN()
    end)
    local t_source_hot, source_handle_hot = timeit(COMPILE_ITERS, function()
        return HOT_SOURCE_FN()
    end)

    assert(builder_handle_cold(N) == source_handle_cold(N))
    assert(builder_handle_hot(N) == source_handle_hot(N))

    print_avg("builder compile cold", "ms", t_builder_cold, COMPILE_ITERS, builder_handle_cold(N))
    print_avg("source compile cold", "ms", t_source_cold, COMPILE_ITERS, source_handle_cold(N))
    print_avg("builder compile hot", "ms", t_builder_hot, COMPILE_ITERS, builder_handle_hot(N))
    print_avg("source compile hot", "ms", t_source_hot, COMPILE_ITERS, source_handle_hot(N))
    print_pair("compile gap cold", "ms", "builder", t_builder_cold, COMPILE_ITERS, "source", t_source_cold, COMPILE_ITERS)
    print_pair("compile gap hot", "ms", "builder", t_builder_hot, COMPILE_ITERS, "source", t_source_hot, COMPILE_ITERS)
    print("")
end

local function bench_module_compile_split()
    print("MODULE COMPILE SPLIT")
    local t_builder_cold, builder_mod_cold = timeit(COMPILE_ITERS, function(i)
        return make_builder_module(i)()
    end)
    local t_source_parse_hot, source_mod_ast = timeit(COMPILE_ITERS, function()
        return parse.module(HOT_MODULE_TEXT)
    end)
    local t_source_lower_hot, source_mod_lowered = timeit(COMPILE_ITERS, function()
        return lower.module(HOT_MODULE_AST)
    end)
    local t_source_cold, source_mod_cold = timeit(COMPILE_ITERS, function(i)
        return module(make_source_module_text(i))()
    end)
    local t_source_hot, source_mod_hot = timeit(COMPILE_ITERS, function()
        return HOT_SOURCE_MODULE()
    end)

    local cold_builder_name = "bench_front_builder_mix_" .. COMPILE_ITERS
    local cold_source_name = "mix_" .. COMPILE_ITERS
    assert(builder_mod_cold[cold_builder_name](19) == source_mod_cold[cold_source_name](19))
    assert(HOT_BUILDER_COMPILED_MODULE.bench_front_builder_mix_hot(19) == source_mod_hot.mix_hot(19))
    assert(source_mod_ast ~= nil and source_mod_lowered ~= nil)

    print_avg("builder module cold", "ms", t_builder_cold, COMPILE_ITERS, builder_mod_cold[cold_builder_name](19))
    print_avg("module ast parse", "us", t_source_parse_hot, COMPILE_ITERS, "<ast>")
    print_avg("module lua lower", "us", t_source_lower_hot, COMPILE_ITERS, tostring(source_mod_lowered))
    print_avg("source module cold", "ms", t_source_cold, COMPILE_ITERS, source_mod_cold[cold_source_name](19))
    print_avg("source module hot", "ms", t_source_hot, COMPILE_ITERS, source_mod_hot.mix_hot(19))
    print_pair("module gap cold", "ms", "builder", t_builder_cold, COMPILE_ITERS, "source", t_source_cold, COMPILE_ITERS)
    print("")
end

local function bench_host_call_split()
    print("COMPILED HOST CALL")
    local t_builder, out_builder = timeit(CALL_ITERS, function()
        return HOT_BUILDER_HANDLE(N)
    end)
    local t_source, out_source = timeit(CALL_ITERS, function()
        return HOT_SOURCE_HANDLE(N)
    end)
    assert(out_builder == out_source)
    print_avg("builder host call", "ns", t_builder, CALL_ITERS, out_builder)
    print_avg("source host call", "ns", t_source, CALL_ITERS, out_source)
    print_pair("host-call gap", "ns", "builder", t_builder, CALL_ITERS, "source", t_source, CALL_ITERS)
    print("")
end

print(string.format(
    "moonlift frontend bench: build_iters=%d compile_iters=%d call_iters=%d n=%d",
    BUILD_ITERS,
    COMPILE_ITERS,
    CALL_ITERS,
    N
))
print("")
bench_function_build_split()
bench_function_compile_split()
bench_module_compile_split()
bench_host_call_split()
