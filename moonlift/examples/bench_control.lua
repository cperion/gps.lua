local ml = require("moonlift")
ml.use()

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    local n = tonumber(v)
    return n or default
end

local N = getenv_num("MOONLIFT_BENCH_CONTROL_N", 200000)
local ITERS = getenv_num("MOONLIFT_BENCH_CONTROL_ITERS", 120)

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

local function bench_case(name, lua_fn, moonlift_fn)
    lua_fn()
    moonlift_fn()
    local t_lua, out_lua = timeit(ITERS, lua_fn)
    local t_ml, out_ml = timeit(ITERS, moonlift_fn)
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

local affine_sum = (func "bench_control_affine_sum") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                acc:set(acc + sext(i64, i * i32(3) + i32(7)))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local branch_sum = (func "bench_control_branch_sum") {
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

local switch_sum = (func "bench_control_switch_sum") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                local key = let(i % i32(5))
                local term = let(switch_(key, {
                    [i32(0)] = function() return i + i32(1) end,
                    [i32(1)] = function() return i * i32(2) end,
                    [i32(2)] = function() return i - i32(3) end,
                    [i32(3)] = function() return i / i32(2) end,
                    default = function() return i * i32(3) + i32(7) end,
                }))
                acc:set(acc + sext(i64, term))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local guarded_sum = (func "bench_control_guarded_sum") {
    i32"n",
    function(n)
        return block(function()
            local i = var(i32(0))
            local acc = var(i64(0))
            while_(i:lt(n), function()
                local one_based = let(i + i32(1))
                local keep = let(((one_based % i32(7)):ne(i32(0))):and_((one_based % i32(11)):ne(i32(0))))
                local term = let(keep(one_based, i32(0)))
                acc:set(acc + sext(i64, term))
                i:set(i + i32(1))
            end)
            return acc
        end)
    end,
}

local affine_sum_h = affine_sum()
local branch_sum_h = branch_sum()
local switch_sum_h = switch_sum()
local guarded_sum_h = guarded_sum()

local function lua_affine_sum()
    local acc = 0
    for i = 0, N - 1 do
        acc = acc + (i * 3 + 7)
    end
    return acc
end

local function lua_branch_sum()
    local acc = 0
    for i = 0, N - 1 do
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

local function lua_switch_sum()
    local acc = 0
    for i = 0, N - 1 do
        local key = i % 5
        local term
        if key == 0 then
            term = i + 1
        elseif key == 1 then
            term = i * 2
        elseif key == 2 then
            term = i - 3
        elseif key == 3 then
            term = math.floor(i / 2)
        else
            term = i * 3 + 7
        end
        acc = acc + term
    end
    return acc
end

local function lua_guarded_sum()
    local acc = 0
    for i = 1, N do
        if (i % 7) ~= 0 and (i % 11) ~= 0 then
            acc = acc + i
        end
    end
    return acc
end

print(string.format("moonlift control bench: n=%d iters=%d", N, ITERS))
print("")
bench_case("affine_sum", lua_affine_sum, function() return affine_sum_h(N) end)
bench_case("branch_sum", lua_branch_sum, function() return branch_sum_h(N) end)
bench_case("switch_sum", lua_switch_sum, function() return switch_sum_h(N) end)
bench_case("guarded_sum", lua_guarded_sum, function() return guarded_sum_h(N) end)
