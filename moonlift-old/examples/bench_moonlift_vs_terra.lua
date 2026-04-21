-- Moonlift side of the head-to-head benchmark (canonical loop form)
-- Run with: ./target/release/moonlift run examples/bench_moonlift_vs_terra.lua
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
    return loop i: i64 = 0, acc: i64 = 0 while i < n
        let ip1: i64 = i + 1
    next
        i = ip1
        acc = acc + ip1
    end -> acc
end
]]()

-- 2. Collatz: branch-heavy, unpredictable control flow
local collatz_h = code[[
func collatz_sum(n: i64) -> i64
    return loop x: i64 = 1, total: i64 = 0 while x < n
        let steps: i64 = loop c: i64 = x, steps: i64 = 0 while c ~= 1
            let next_c: i64 = if c % 2 == 0 then c / 2 else c * 3 + 1 end
        next
            c = next_c
            steps = steps + 1
        end -> steps
    next
        x = x + 1
        total = total + steps
    end -> total
end
]]()

-- 3. Mandelbrot: floating-point + branches
local mandelbrot_h = code[[
func mandelbrot_sum(width: i32, height: i32, max_iter: i32) -> i64
    return loop py: i32 = 0, total: i64 = 0 while py < height
        let row_total: i64 = loop px: i32 = 0, row_total: i64 = 0 while px < width
            let x0: f64 = (cast<f64>(px) / cast<f64>(width)) * 3.5 - 2.5
            let y0: f64 = (cast<f64>(py) / cast<f64>(height)) * 2.0 - 1.0
            let iter64: i64 = cast<i64>(loop x: f64 = 0.0, y: f64 = 0.0, iter: i32 = 0 while x * x + y * y < 4.0 and iter < max_iter
                let xtemp: f64 = x * x - y * y + x0
                let ynext: f64 = 2.0 * x * y + y0
            next
                x = xtemp
                y = ynext
                iter = iter + 1
            end -> iter)
        next
            px = px + 1
            row_total = row_total + iter64
        end -> row_total
    next
        py = py + 1
        total = total + row_total
    end -> total
end
]]()

-- 4. Polynomial grid: nested loop, float math
local poly_h = code[[
func poly_eval_grid(n: i32) -> f64
    return loop i: i32 = 0, total: f64 = 0.0 while i < n
        let x: f64 = cast<f64>(i) / cast<f64>(n)
        let row_total: f64 = loop j: i32 = 0, row_total: f64 = 0.0 while j < n
            let y: f64 = cast<f64>(j) / cast<f64>(n)
            let r: f64 = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
        next
            j = j + 1
            row_total = row_total + r
        end -> row_total
    next
        i = i + 1
        total = total + row_total
    end -> total
end
]]()

-- 5. Popcount: bitwise ops + unpredictable inner loop
local popcount_h = code[[
func popcount_sum(n: i64) -> i64
    return loop i: i64 = 0, total: i64 = 0 while i < n
        let bits: i64 = loop x: i64 = i, bits: i64 = 0 while x ~= 0
        next
            x = x >>> 1
            bits = bits + (x & 1)
        end -> bits
    next
        i = i + 1
        total = total + bits
    end -> total
end
]]()

-- 6. Fibonacci iterative (tight loop, data dependency chain)
local fib_h = code[[
func fib_sum(n: i64) -> i64
    return loop k: i64 = 1, total: i64 = 0 while k < n
        let b_final: i64 = loop a: i64 = 0, b: i64 = 1, i: i64 = 0 while i < k % 90
            let c: i64 = a + b
        next
            a = b
            b = c
            i = i + 1
        end -> b
    next
        k = k + 1
        total = total + b_final
    end -> total
end
]]()

-- 7. GCD sum: division-heavy inner loop
local gcd_h = code[[
func gcd_sum(n: i64) -> i64
    return loop i: i64 = 1, total: i64 = 0 while i < n
        let row_total: i64 = loop j: i64 = i + 1, row_total: i64 = 0 while j < i + 16
            let g: i64 = loop a: i64 = i, b: i64 = j while b ~= 0
                let t: i64 = b
            next
                a = t
                b = a % b
            end -> a
        next
            j = j + 1
            row_total = row_total + g
        end -> row_total
    next
        i = i + 1
        total = total + row_total
    end -> total
end
]]()

-- 8. Switch dispatch: multi-way branch
local switch_h = code[[
func switch_sum(n: i64) -> i64
    return loop i: i64 = 0, acc: i64 = 0 while i < n
        let r: i64 = i % 7
        var next_acc: i64 = acc
        if r == 0 then
            next_acc = next_acc + 1
        else if r == 1 then
            next_acc = next_acc + 3
        else if r == 2 then
            next_acc = next_acc + 5
        else if r == 3 then
            next_acc = next_acc + 7
        else if r == 4 then
            next_acc = next_acc + 11
        else if r == 5 then
            next_acc = next_acc + 13
        else
            next_acc = next_acc + 17
        end end end end end end
    next
        i = i + 1
        acc = next_acc
    end -> acc
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
