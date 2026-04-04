package.path = "./?.lua;./?/init.lua;" .. package.path

local iterkit = require("iterkit")
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
    io.write(string.format("  %-28s %8.1f us\n", label, dt * 1e6))
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

local function build_pipelines(it)
    return {
        basic = it.range(1, 100000):filter(odd, "odd"):map(square, "square"):take(10000),
        chain = it.once(0):chain(it.range(1, 50000):skip(100):take(5000)),
        scan = it.range(1, 20000):scan(add, 0, "add"):take(5000),
        dedup = it.from({1,1,1,2,2,3,3,3,4,5,5,6,6,6,7,7,8,9,9,9}):dedup(),
        enum = it.chars("abcdefghijklmnopqrstuvwxyz"):enumerate(10),
    }
end

local k = build_pipelines(iterkit)
local i2 = build_pipelines(iter2)

-- correctness
assert(same_array(k.basic:collect(), i2.basic:collect()))
assert(same_array(k.chain:collect(), i2.chain:collect()))
assert(same_array(k.scan:collect(), i2.scan:collect()))
assert(same_array(k.dedup:collect(), i2.dedup:collect()))
assert(same_array(k.enum:collect(), i2.enum:collect()))
assert(same_array(k.basic:compile():collect(), i2.basic:compile():collect()))
assert(k.basic:sum() == i2.basic:sum())
assert(k.basic:compile():sum() == i2.basic:compile():sum())
print("Correctness: OK")
print()

print("iterkit vs iter2")
print("══════════════════════════════════════════════")
print("Notes:")
print("  iterkit = plain-table tagged pipeline nodes")
print("  iter2   = ASDL/PVM interned pipeline nodes")
print("  compiled paths are Quote-generated fused reducers")
print()

local workloads = {
    { name = "basic", pipe_k = k.basic, pipe_i2 = i2.basic, n_collect = 200, n_sum = 500 },
    { name = "chain", pipe_k = k.chain, pipe_i2 = i2.chain, n_collect = 500, n_sum = 1000 },
    { name = "scan",  pipe_k = k.scan,  pipe_i2 = i2.scan,  n_collect = 500, n_sum = 1000 },
}

for _, w in ipairs(workloads) do
    print("── " .. w.name .. " ──")
    local ck, ci2 = w.pipe_k:compile(), w.pipe_i2:compile()

    local _, tk_i = bench("iterkit collect", function() return w.pipe_k:collect() end, w.n_collect)
    local _, tk_c = bench("iterkit compiled", function() return ck:collect() end, w.n_collect)
    local _, t2_i = bench("iter2 collect", function() return w.pipe_i2:collect() end, w.n_collect)
    local _, t2_c = bench("iter2 compiled", function() return ci2:collect() end, w.n_collect)
    local _, sk_i = bench("iterkit sum", function() return w.pipe_k:sum() end, w.n_sum)
    local _, sk_c = bench("iterkit compiled sum", function() return ck:sum() end, w.n_sum)
    local _, s2_i = bench("iter2 sum", function() return w.pipe_i2:sum() end, w.n_sum)
    local _, s2_c = bench("iter2 compiled sum", function() return ci2:sum() end, w.n_sum)

    print(string.format("  collect speedup: iterkit %.2fx, iter2 %.2fx", tk_i / tk_c, t2_i / t2_c))
    print(string.format("  sum speedup:     iterkit %.2fx, iter2 %.2fx", sk_i / sk_c, s2_i / s2_c))
    print()
end

print("Lowering cache stats (iter2):")
local collect_stats = iter2.lowerings.collect:stats()
local sum_stats = iter2.lowerings.sum:stats()
print(string.format("  collect calls=%d hits=%d", collect_stats.calls, collect_stats.hits))
print(string.format("  sum     calls=%d hits=%d", sum_stats.calls, sum_stats.hits))
print()
print("Example generated source (iter2 collect, basic):")
print(i2.basic:compile():source("collect"))
