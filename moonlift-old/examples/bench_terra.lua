-- Terra side of the head-to-head benchmark
-- Run with: terra examples/bench_terra.lua

local WARMUP = 3
local ITERS = 5

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

-- 1. Sum loop: pure integer accumulation
local terra sum_loop(n: int64): int64
    var acc: int64 = 0
    var i: int64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

-- 2. Collatz: branch-heavy, unpredictable control flow
local terra collatz_sum(n: int64): int64
    var total: int64 = 0
    var x: int64 = 1
    while x < n do
        var c: int64 = x
        var steps: int64 = 0
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

-- 3. Mandelbrot: floating-point + branches
local terra mandelbrot_sum(width: int32, height: int32, max_iter: int32): int64
    var total: int64 = 0
    var py: int32 = 0
    while py < height do
        var px: int32 = 0
        while px < width do
            var x0: double = (([double](px) / [double](width)) * 3.5) - 2.5
            var y0: double = (([double](py) / [double](height)) * 2.0) - 1.0
            var x: double = 0.0
            var y: double = 0.0
            var iter: int32 = 0
            while (x * x + y * y) < 4.0 and iter < max_iter do
                var xtemp: double = x * x - y * y + x0
                y = 2.0 * x * y + y0
                x = xtemp
                iter = iter + 1
            end
            total = total + iter
            px = px + 1
        end
        py = py + 1
    end
    return total
end

-- 4. Polynomial grid: nested loop, float math
local terra poly_eval_grid(n: int32): double
    var total: double = 0.0
    var i: int32 = 0
    while i < n do
        var x: double = [double](i) / [double](n)
        var j: int32 = 0
        while j < n do
            var y: double = [double](j) / [double](n)
            var r: double = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
            total = total + r
            j = j + 1
        end
        i = i + 1
    end
    return total
end

-- 5. Popcount: bitwise ops + unpredictable inner loop
local terra popcount_sum(n: int64): int64
    var total: int64 = 0
    var i: int64 = 0
    while i < n do
        var x: int64 = i
        var bits: int64 = 0
        while x ~= 0 do
            bits = bits + (x and 1)
            x = [uint64](x) >> 1
        end
        total = total + bits
        i = i + 1
    end
    return total
end

-- 6. Fibonacci iterative (tight loop, data dependency chain)
local terra fib_sum(n: int64): int64
    var total: int64 = 0
    var k: int64 = 1
    while k < n do
        var a: int64 = 0
        var b: int64 = 1
        var i: int64 = 0
        while i < k % 90 do
            var c: int64 = a + b
            a = b
            b = c
            i = i + 1
        end
        total = total + b
        k = k + 1
    end
    return total
end

-- 7. GCD sum: division-heavy inner loop
local terra gcd_sum(n: int64): int64
    var total: int64 = 0
    var i: int64 = 1
    while i < n do
        var j: int64 = i + 1
        while j < i + 16 do
            var a: int64 = i
            var b: int64 = j
            while b ~= 0 do
                var t: int64 = b
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

-- 8. Switch dispatch: multi-way branch
local terra switch_sum(n: int64): int64
    var acc: int64 = 0
    var i: int64 = 0
    while i < n do
        var r: int64 = i % 7
        if r == 0 then
            acc = acc + 1
        elseif r == 1 then
            acc = acc + 3
        elseif r == 2 then
            acc = acc + 5
        elseif r == 3 then
            acc = acc + 7
        elseif r == 4 then
            acc = acc + 11
        elseif r == 5 then
            acc = acc + 13
        else
            acc = acc + 17
        end
        i = i + 1
    end
    return acc
end

---------- compile all ----------
local t_compile_start = os.clock()
sum_loop:compile()
collatz_sum:compile()
mandelbrot_sum:compile()
poly_eval_grid:compile()
popcount_sum:compile()
fib_sum:compile()
gcd_sum:compile()
switch_sum:compile()
local t_compile_end = os.clock()

---------- run benchmarks ----------
io.write(string.format("COMPILE_ALL %.6f\n", (t_compile_end - t_compile_start)))

local N_SUM = 100000000
local t = bench("sum_loop", sum_loop, N_SUM)
io.write(string.format("sum_loop %.6f %d\n", t, sum_loop(N_SUM)))

local N_COLLATZ = 5000000
local t = bench("collatz", collatz_sum, N_COLLATZ)
io.write(string.format("collatz %.6f %d\n", t, collatz_sum(N_COLLATZ)))

local MW, MH, MI = 512, 512, 256
local t = bench("mandelbrot", mandelbrot_sum, MW, MH, MI)
io.write(string.format("mandelbrot %.6f %d\n", t, mandelbrot_sum(MW, MH, MI)))

local N_POLY = 1000
local t = bench("poly_grid", poly_eval_grid, N_POLY)
io.write(string.format("poly_grid %.6f %.6f\n", t, poly_eval_grid(N_POLY)))

local N_POP = 10000000
local t = bench("popcount", popcount_sum, N_POP)
io.write(string.format("popcount %.6f %d\n", t, popcount_sum(N_POP)))

local N_FIB = 1000000
local t = bench("fib_sum", fib_sum, N_FIB)
io.write(string.format("fib_sum %.6f %d\n", t, fib_sum(N_FIB)))

local N_GCD = 500000
local t = bench("gcd_sum", gcd_sum, N_GCD)
io.write(string.format("gcd_sum %.6f %d\n", t, gcd_sum(N_GCD)))

local N_SWITCH = 50000000
local t = bench("switch_sum", switch_sum, N_SWITCH)
io.write(string.format("switch_sum %.6f %d\n", t, switch_sum(N_SWITCH)))
