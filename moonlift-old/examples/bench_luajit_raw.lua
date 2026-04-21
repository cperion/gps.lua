-- Raw LuaJIT side of the head-to-head benchmark.
-- Run with: ./target/release/moonlift run examples/bench_luajit_raw.lua
-- This file intentionally uses plain LuaJIT+FFI code, not Moonlift.

local ffi = require('ffi')
local bit = require('bit')

local WARMUP = 3
local ITERS = 5
local int64 = ffi.typeof('int64_t')

local function exact(v)
    if type(v) == 'cdata' then
        if ffi.istype('int64_t', v) then return string.format('%d', v) end
        if ffi.istype('uint64_t', v) then return string.format('%u', v) end
    elseif type(v) == 'number' and v == math.floor(v) then
        return string.format('%.0f', v)
    end
    return tostring(v)
end

local function bench(f, ...)
    for _ = 1, WARMUP do f(...) end
    local best = math.huge
    for _ = 1, ITERS do
        local t = os.clock()
        f(...)
        local dt = os.clock() - t
        if dt < best then best = dt end
    end
    return best
end

local t_compile_start = os.clock()

local function sum_loop(n)
    local acc = 0
    local i = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

local function collatz_sum(n)
    local total = 0
    local x = 1
    while x < n do
        local c = x
        local steps = 0
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

local function mandelbrot_sum(width, height, max_iter)
    local total = 0
    local py = 0
    while py < height do
        local px = 0
        while px < width do
            local x0 = (px / width) * 3.5 - 2.5
            local y0 = (py / height) * 2.0 - 1.0
            local x = 0.0
            local y = 0.0
            local iter = 0
            while (x * x + y * y) < 4.0 and iter < max_iter do
                local xtemp = x * x - y * y + x0
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

local function poly_eval_grid(n)
    local total = 0.0
    local i = 0
    while i < n do
        local x = i / n
        local j = 0
        while j < n do
            local y = j / n
            local r = 3.0*x*x*x + 2.0*x*x*y - x*y*y + y*y*y
            total = total + r
            j = j + 1
        end
        i = i + 1
    end
    return total
end

local function popcount_sum(n)
    local total = 0
    local i = 0
    while i < n do
        local x = i
        local bits = 0
        while x ~= 0 do
            bits = bits + bit.band(x, 1)
            x = bit.rshift(x, 1)
        end
        total = total + bits
        i = i + 1
    end
    return total
end

-- Use FFI int64 here to preserve the same wrapped i64 semantics as Moonlift/Terra.
local function fib_sum(n)
    local total = int64(0)
    local k = 1
    while k < n do
        local a = int64(0)
        local b = int64(1)
        local i = 0
        local limit = k % 90
        while i < limit do
            local c = a + b
            a = b
            b = c
            i = i + 1
        end
        total = total + b
        k = k + 1
    end
    return total
end

local function gcd_sum(n)
    local total = 0
    local i = 1
    while i < n do
        local j = i + 1
        while j < i + 16 do
            local a = i
            local b = j
            while b ~= 0 do
                local t = b
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

local function switch_sum(n)
    local acc = 0
    local i = 0
    while i < n do
        local r = i % 7
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

local t_compile_end = os.clock()
io.write(string.format('COMPILE_ALL %.6f\n', t_compile_end - t_compile_start))

local N_SUM = 100000000
local t = bench(sum_loop, N_SUM)
io.write(string.format('sum_loop %.6f %s\n', t, exact(sum_loop(N_SUM))))

local N_COLLATZ = 5000000
t = bench(collatz_sum, N_COLLATZ)
io.write(string.format('collatz %.6f %s\n', t, exact(collatz_sum(N_COLLATZ))))

local MW, MH, MI = 512, 512, 256
t = bench(mandelbrot_sum, MW, MH, MI)
io.write(string.format('mandelbrot %.6f %s\n', t, exact(mandelbrot_sum(MW, MH, MI))))

local N_POLY = 1000
t = bench(poly_eval_grid, N_POLY)
io.write(string.format('poly_grid %.6f %.6f\n', t, poly_eval_grid(N_POLY)))

local N_POP = 10000000
t = bench(popcount_sum, N_POP)
io.write(string.format('popcount %.6f %s\n', t, exact(popcount_sum(N_POP))))

local N_FIB = 1000000
t = bench(fib_sum, N_FIB)
io.write(string.format('fib_sum %.6f %s\n', t, exact(fib_sum(N_FIB))))

local N_GCD = 500000
t = bench(gcd_sum, N_GCD)
io.write(string.format('gcd_sum %.6f %s\n', t, exact(gcd_sum(N_GCD))))

local N_SWITCH = 50000000
t = bench(switch_sum, N_SWITCH)
io.write(string.format('switch_sum %.6f %s\n', t, exact(switch_sum(N_SWITCH))))
