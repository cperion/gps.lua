-- Moonlift side of the head-to-head benchmark (old while-loop form)
-- Run with: ./target/release/moonlift run examples/bench_moonlift_vs_terra_oldloops.lua
local ml = require('moonlift')
ml.use()

local WARMUP = 3
local ITERS = 5
local exact = ml.exact_tostring

local function bench(name, f, ...)
    for i = 1, WARMUP do f(...) end
    local best = math.huge
    for i = 1, ITERS do
        local t = os.clock()
        local r = f(...)
        local elapsed = os.clock() - t
        if elapsed < best then best = elapsed end
    end
    return best
end

---------- compile all kernels ----------
local t_compile_start = os.clock()

-- 1. Sum loop: pure integer accumulation
local sum_loop_h = code[[
func sum_loop(n: i64) -> i64
    var acc: i64 = 0
    var i: i64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]()

-- 2. Collatz: branch-heavy, unpredictable control flow
local collatz_h = code[[
func collatz_sum(n: i64) -> i64
    var total: i64 = 0
    var x: i64 = 1
    while x < n do
        var c: i64 = x
        var steps: i64 = 0
        while c ~= 1 do
            if c % 2 == 0 then
                c = c / 2
            else
                c = c * 3 + 1
            end
            steps = steps + 1
        end
        total = total + steps
        x = x + 1
    end
    return total
end
]]()

-- 3. Mandelbrot: floating-point + branches
local mandelbrot_h = code[[
func mandelbrot_sum(width: i32, height: i32, max_iter: i32) -> i64
    var total: i64 = 0
    var py: i32 = 0
    while py < height do
        var px: i32 = 0
        while px < width do
            let x0: f64 = (cast<f64>(px) / cast<f64>(width)) * 3.5 - 2.5
            let y0: f64 = (cast<f64>(py) / cast<f64>(height)) * 2.0 - 1.0
            var x: f64 = 0.0
            var y: f64 = 0.0
            var iter: i32 = 0
            while x * x + y * y < 4.0 and iter < max_iter do
                let xtemp: f64 = x * x - y * y + x0
                y = 2.0 * x * y + y0
                x = xtemp
                iter = iter + 1
            end
            total = total + cast<i64>(iter)
            px = px + 1
        end
        py = py + 1
    end
    return total
end
]]()

-- 4. Polynomial grid: nested loop, float math
local poly_h = code[[
func poly_eval_grid(n: i32) -> f64
    var total: f64 = 0.0
    var i: i32 = 0
    while i < n do
        let x: f64 = cast<f64>(i) / cast<f64>(n)
        var j: i32 = 0
        while j < n do
            let y: f64 = cast<f64>(j) / cast<f64>(n)
            let r: f64 = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
            total = total + r
            j = j + 1
        end
        i = i + 1
    end
    return total
end
]]()

-- 5. Popcount: bitwise ops + unpredictable inner loop
local popcount_h = code[[
func popcount_sum(n: i64) -> i64
    var total: i64 = 0
    var i: i64 = 0
    while i < n do
        var x: i64 = i
        var bits: i64 = 0
        while x ~= 0 do
            bits = bits + (x & 1)
            x = x >>> 1
        end
        total = total + bits
        i = i + 1
    end
    return total
end
]]()

-- 6. Fibonacci iterative (tight loop, data dependency chain)
local fib_h = code[[
func fib_sum(n: i64) -> i64
    var total: i64 = 0
    var k: i64 = 1
    while k < n do
        var a: i64 = 0
        var b: i64 = 1
        var i: i64 = 0
        while i < k % 90 do
            let c: i64 = a + b
            a = b
            b = c
            i = i + 1
        end
        total = total + b
        k = k + 1
    end
    return total
end
]]()

-- 7. GCD sum: division-heavy inner loop
local gcd_h = code[[
func gcd_sum(n: i64) -> i64
    var total: i64 = 0
    var i: i64 = 1
    while i < n do
        var j: i64 = i + 1
        while j < i + 16 do
            var a: i64 = i
            var b: i64 = j
            while b ~= 0 do
                let t: i64 = b
                b = a % b
                a = t
            end
            total = total + a
            j = j + 1
        end
        i = i + 1
    end
    return total
end
]]()

-- 8. Switch dispatch: multi-way branch
local switch_h = code[[
func switch_sum(n: i64) -> i64
    var acc: i64 = 0
    var i: i64 = 0
    while i < n do
        let r: i64 = i % 7
        if r == 0 then
            acc = acc + 1
        else if r == 1 then
            acc = acc + 3
        else if r == 2 then
            acc = acc + 5
        else if r == 3 then
            acc = acc + 7
        else if r == 4 then
            acc = acc + 11
        else if r == 5 then
            acc = acc + 13
        else
            acc = acc + 17
        end end end end end end
        i = i + 1
    end
    return acc
end
]]()

local t_compile_end = os.clock()

---------- run benchmarks ----------
io.write(string.format("COMPILE_ALL %.6f\n", (t_compile_end - t_compile_start)))

local N_SUM = 100000000
local t = bench("sum_loop", sum_loop_h, N_SUM)
io.write(string.format("sum_loop %.6f %s\n", t, exact(sum_loop_h(N_SUM))))

local N_COLLATZ = 5000000
local t = bench("collatz", collatz_h, N_COLLATZ)
io.write(string.format("collatz %.6f %s\n", t, exact(collatz_h(N_COLLATZ))))

local MW, MH, MI = 512, 512, 256
local t = bench("mandelbrot", mandelbrot_h, MW, MH, MI)
io.write(string.format("mandelbrot %.6f %s\n", t, exact(mandelbrot_h(MW, MH, MI))))

local N_POLY = 1000
local t = bench("poly_grid", poly_h, N_POLY)
io.write(string.format("poly_grid %.6f %.6f\n", t, poly_h(N_POLY)))

local N_POP = 10000000
local t = bench("popcount", popcount_h, N_POP)
io.write(string.format("popcount %.6f %s\n", t, exact(popcount_h(N_POP))))

local N_FIB = 1000000
local t = bench("fib_sum", fib_h, N_FIB)
io.write(string.format("fib_sum %.6f %s\n", t, exact(fib_h(N_FIB))))

local N_GCD = 500000
local t = bench("gcd_sum", gcd_h, N_GCD)
io.write(string.format("gcd_sum %.6f %s\n", t, exact(gcd_h(N_GCD))))

local N_SWITCH = 50000000
local t = bench("switch_sum", switch_h, N_SWITCH)
io.write(string.format("switch_sum %.6f %s\n", t, exact(switch_h(N_SWITCH))))
