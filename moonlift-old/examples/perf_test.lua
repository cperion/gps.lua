local ml = require('moonlift')
ml.use()

print('=== Moonlift vs LuaJIT Performance ===\n')

local N = 10000000

local sum_loop = code[[
func sum_loop(n: i64) -> i64
    var i: i64 = 0
    var acc: i64 = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end
]]
local sum_loop_h = sum_loop()

local function sum_loop_lua(n)
    local i = 0
    local acc = 0
    while i < n do
        i = i + 1
        acc = acc + i
    end
    return acc
end

print('--- Sum Loop (n=' .. N .. ') ---')
local t1 = os.clock()
local r1 = sum_loop_h(N)
local t2 = os.clock()
print(string.format('Moonlift: %.3f ms  result=%d', (t2 - t1) * 1000, r1))

local t3 = os.clock()
local r2 = sum_loop_lua(N)
local t4 = os.clock()
print(string.format('LuaJIT:   %.3f ms  result=%d', (t4 - t3) * 1000, r2))
print(string.format('Speedup:  %.2fx', (t4 - t3) / (t2 - t1)))

local fib_mod = module[[
func fib(n: i32) -> i64
    var a: i64 = 0
    var b: i64 = 1
    var i: i32 = 0
    while i < n do
        var tmp: i64 = a + b
        a = b
        b = tmp
        i = i + 1
    end
    return a
end

func fib_sum(count: i32) -> i64
    var acc: i64 = 0
    var i: i32 = 0
    while i < count do
        acc = acc + fib(i % 50)
        i = i + 1
    end
    return acc
end
]]
local fib_mod_c = fib_mod()
local fib_sum_h = fib_mod_c.fib_sum

local function fib_lua(n)
    if n <= 1 then return n end
    local a, b = 0, 1
    for i = 2, n do
        a, b = b, a + b
    end
    return b
end

local function fib_sum_lua(count)
    local acc = 0
    for i = 0, count - 1 do
        acc = acc + fib_lua(i % 50)
    end
    return acc
end

print('\n--- Fibonacci Sum (count=' .. N .. ') ---')
local t9 = os.clock()
local r5 = fib_sum_h(N)
local t10 = os.clock()
print(string.format('Moonlift: %.3f ms  sum=%d', (t10 - t9) * 1000, r5))

local t11 = os.clock()
local r6 = fib_sum_lua(N)
local t12 = os.clock()
print(string.format('LuaJIT:   %.3f ms  sum=%d', (t12 - t11) * 1000, r6))
print(string.format('Speedup:  %.2fx', (t12 - t11) / (t10 - t9)))

local mandel_mod = module[[
func mandel(cx: f64, cy: f64, max_iter: i32) -> i32
    var x: f64 = 0.0
    var y: f64 = 0.0
    var iter: i32 = 0
    while x * x + y * y <= 4.0 and iter < max_iter do
        var xtmp: f64 = x * x - y * y + cx
        y = 2.0 * x * y + cy
        x = xtmp
        iter = iter + 1
    end
    return iter
end

func mandel_grid(w: i32, h: i32, max_iter: i32) -> i32
    var total: i32 = 0
    var py: i32 = 0
    while py < h do
        var px: i32 = 0
        while px < w do
            var cx: f64 = -2.5 + 3.5 * (cast<f64>(px) / cast<f64>(w))
            var cy: f64 = -1.0 + 2.0 * (cast<f64>(py) / cast<f64>(h))
            total = total + mandel(cx, cy, max_iter)
            px = px + 1
        end
        py = py + 1
    end
    return total
end
]]
local mandel_mod_c = mandel_mod()
local mandel_h = mandel_mod_c.mandel_grid

local function mandel_lua(cx, cy, max_iter)
    local x, y = 0.0, 0.0
    local iter = 0
    while x * x + y * y <= 4.0 and iter < max_iter do
        local xtmp = x * x - y * y + cx
        y = 2.0 * x * y + cy
        x = xtmp
        iter = iter + 1
    end
    return iter
end

local function mandel_grid_lua(w, h, max_iter)
    local total = 0
    for py = 0, h - 1 do
        for px = 0, w - 1 do
            local cx = -2.5 + 3.5 * (px / w)
            local cy = -1.0 + 2.0 * (py / h)
            total = total + mandel_lua(cx, cy, max_iter)
        end
    end
    return total
end

local W, H, MAX_ITER = 400, 300, 100

print('\n--- Mandelbrot Grid (' .. W .. 'x' .. H .. ', max_iter=' .. MAX_ITER .. ') ---')
local t13 = os.clock()
local r7 = mandel_h(W, H, MAX_ITER)
local t14 = os.clock()
print(string.format('Moonlift: %.3f ms  total=%d', (t14 - t13) * 1000, r7))

local t15 = os.clock()
local r8 = mandel_grid_lua(W, H, MAX_ITER)
local t16 = os.clock()
print(string.format('LuaJIT:   %.3f ms  total=%d', (t16 - t15) * 1000, r8))
print(string.format('Speedup:  %.2fx', (t16 - t15) / (t14 - t13)))

local switch_bench = code[[
func switch_bench(n: i32) -> i32
    var acc: i32 = 0
    var i: i32 = 0
    while i < n do
        var r: i32 = i % 8
        switch r do
        case 0 then
            acc = acc + 1
        case 1 then
            acc = acc + 2
        case 2 then
            acc = acc + 3
        case 3 then
            acc = acc + 4
        case 4 then
            acc = acc + 5
        case 5 then
            acc = acc + 6
        case 6 then
            acc = acc + 7
        case 7 then
            acc = acc + 8
        end
        i = i + 1
    end
    return acc
end
]]
local switch_h = switch_bench()

local function switch_bench_lua(n)
    local acc = 0
    for i = 0, n - 1 do
        local r = i % 8
        if r == 0 then acc = acc + 1
        elseif r == 1 then acc = acc + 2
        elseif r == 2 then acc = acc + 3
        elseif r == 3 then acc = acc + 4
        elseif r == 4 then acc = acc + 5
        elseif r == 5 then acc = acc + 6
        elseif r == 6 then acc = acc + 7
        else acc = acc + 8
        end
    end
    return acc
end

print('\n--- Switch Dispatch (n=' .. N .. ') ---')
local t17 = os.clock()
local r9 = switch_h(N)
local t18 = os.clock()
print(string.format('Moonlift: %.3f ms  result=%d', (t18 - t17) * 1000, r9))

local t19 = os.clock()
local r10 = switch_bench_lua(N)
local t20 = os.clock()
print(string.format('LuaJIT:   %.3f ms  result=%d', (t20 - t19) * 1000, r10))
print(string.format('Speedup:  %.2fx', (t20 - t19) / (t18 - t17)))

print('\n=== Done ===')
