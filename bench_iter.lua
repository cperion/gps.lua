package.path = "./?.lua;./?/init.lua;" .. package.path

local iter = require("iter")
local iter2 = require("iter2")

local function bench(label, fn, n)
    n = n or 1000
    for _ = 1, math.min(n, 100) do fn() end
    collectgarbage("collect")
    collectgarbage("stop")
    local t0 = os.clock()
    local sink
    for _ = 1, n do sink = fn() end
    local dt = (os.clock() - t0) / n
    collectgarbage("restart")
    io.write(string.format("  %-24s %9.3f us\n", label, dt * 1e6))
    return sink, dt
end

local function bench_cold_iter2(label, reducer, fn, n)
    n = n or 100
    local lower = assert(iter2.lowerings[reducer], "missing iter2 lowering: " .. tostring(reducer))
    local normalize = iter2.normalize

    for _ = 1, math.min(n, 20) do
        normalize:reset()
        lower:reset()
        fn()
    end

    collectgarbage("collect")
    collectgarbage("stop")
    local t0 = os.clock()
    local sink
    for _ = 1, n do
        normalize:reset()
        lower:reset()
        sink = fn()
    end
    local dt = (os.clock() - t0) / n
    collectgarbage("restart")
    io.write(string.format("  %-24s %9.3f us\n", label, dt * 1e6))
    return sink, dt
end

local function same_array(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local av, bv = a[i], b[i]
        if type(av) == "table" and type(bv) == "table" then
            if not same_array(av, bv) then return false end
        elseif av ~= bv then
            return false
        end
    end
    return true
end

local function odd(x) return x % 2 == 1 end
local function square(x) return x * x end
local function add(a, b) return a + b end

local function call0(obj, reducer)
    return obj[reducer](obj)
end

local function make_runs(groups, run_len)
    local out, n = {}, 0
    for v = 1, groups do
        for _ = 1, run_len do
            n = n + 1
            out[n] = v
        end
    end
    return out
end

local dedup_data = make_runs(5000, 4)

local function basic(lib, hi, take_n)
    return lib.range(1, hi):filter(odd):map(square):take(take_n)
end

local function chain(lib)
    return lib.once(0):chain(lib.range(1, 50000):skip(100):take(5000))
end

local function scan(lib)
    return lib.range(1, 20000):scan(add, 0):take(5000)
end

local function dedup(lib)
    return lib.from(dedup_data):dedup()
end

local workloads = {
    {
        name = "tiny basic / sum",
        reducer = "sum",
        iter = basic(iter, 100, 10),
        iter2 = basic(iter2, 100, 10),
        n_iter = 50000,
        n_cold = 1000,
    },
    {
        name = "tiny basic / collect",
        reducer = "collect",
        iter = basic(iter, 100, 10),
        iter2 = basic(iter2, 100, 10),
        n_iter = 20000,
        n_cold = 500,
    },
    {
        name = "large basic / sum",
        reducer = "sum",
        iter = basic(iter, 100000, 10000),
        iter2 = basic(iter2, 100000, 10000),
        n_iter = 1000,
        n_cold = 100,
    },
    {
        name = "large basic / collect",
        reducer = "collect",
        iter = basic(iter, 100000, 10000),
        iter2 = basic(iter2, 100000, 10000),
        n_iter = 200,
        n_cold = 50,
    },
    {
        name = "chain / sum",
        reducer = "sum",
        iter = chain(iter),
        iter2 = chain(iter2),
        n_iter = 2000,
        n_cold = 200,
    },
    {
        name = "scan / sum",
        reducer = "sum",
        iter = scan(iter),
        iter2 = scan(iter2),
        n_iter = 2000,
        n_cold = 200,
    },
    {
        name = "dedup / collect",
        reducer = "collect",
        iter = dedup(iter),
        iter2 = dedup(iter2),
        n_iter = 500,
        n_cold = 100,
    },
}

-- correctness
for _, w in ipairs(workloads) do
    local ri = call0(w.iter, w.reducer)
    local r2 = call0(w.iter2, w.reducer)
    if type(ri) == "table" then
        assert(same_array(ri, r2), "mismatch for " .. w.name)
    else
        assert(ri == r2, "mismatch for " .. w.name)
    end
end

print("Correctness: OK")
print()
print("iter vs iter2")
print("══════════════════════════════════════════════")
print("Notes:")
print("  iter  = plain triplet VM, no codegen")
print("  iter2 = ASDL/PVM nodes + Quote-generated reducer lowering")
print("  iter2 cold = reset normalize + reducer lowering every run")
print("  iter2 warm = same pipeline, cached lowered reducer")
print()

for _, w in ipairs(workloads) do
    print("── " .. w.name .. " ──")

    local _, t_iter = bench("iter", function()
        return call0(w.iter, w.reducer)
    end, w.n_iter)

    local _, t_cold = bench_cold_iter2("iter2 cold", w.reducer, function()
        return call0(w.iter2, w.reducer)
    end, w.n_cold)

    -- prime warm cache for this reducer
    call0(w.iter2, w.reducer)
    local _, t_warm = bench("iter2 warm", function()
        return call0(w.iter2, w.reducer)
    end, w.n_iter)

    print(string.format("  iter / iter2 cold: %.2fx", t_iter / t_cold))
    print(string.format("  iter / iter2 warm: %.2fx", t_iter / t_warm))
    print()
end

-- quick check: explicit :compile() is basically the same hot path in iter2
local hot_pipe = basic(iter2, 100000, 10000)
local hot_compiled = hot_pipe:compile()
hot_pipe:sum()
hot_compiled:sum()
print("iter2 hot path sanity check")
print("──────────────────────────────────────────────")
local _, t_pipe = bench("Pipe:sum()", function() return hot_pipe:sum() end, 2000)
local _, t_comp = bench("Compile():sum()", function() return hot_compiled:sum() end, 2000)
print(string.format("  ratio: %.2fx", t_pipe / t_comp))
