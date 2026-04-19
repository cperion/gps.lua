local function now_ms()
    return os.clock() * 1000.0
end

local function make_coeffs(taps)
    local coeffs = {}
    local sum = 0.0
    for i = 1, taps do
        local mid = (taps + 1) / 2.0
        local dist = math.abs(i - mid)
        local w = (mid - dist)
        coeffs[i] = w
        sum = sum + w
    end
    for i = 1, taps do
        coeffs[i] = coeffs[i] / sum
    end
    return coeffs
end

local function make_fir(coeffs)
    local taps = #coeffs
    local fir = terra(x: &double, y: &double, n: int32)
        var i: int32 = [taps - 1]
        while i < n do
            var acc: double = 0.0
            [
                (function()
                    local stmts = terralib.newlist()
                    for j = 0, taps - 1 do
                        stmts:insert(quote
                            acc = acc + [coeffs[j + 1]] * x[i - [j]]
                        end)
                    end
                    return stmts
                end)()
            ]
            y[i] = acc
            i = i + 1
        end
    end
    return fir
end

local function fill(ptr, n)
    for i = 0, n - 1 do
        ptr[i] = ((i * 11) % 23) * 0.125 - 1.0
    end
end

local function zero(ptr, n)
    for i = 0, n - 1 do
        ptr[i] = 0.0
    end
end

local function lua_fir(coeffs, x, y, n)
    local taps = #coeffs
    for i = taps - 1, n - 1 do
        local acc = 0.0
        for j = 0, taps - 1 do
            acc = acc + coeffs[j + 1] * x[i - j]
        end
        y[i] = acc
    end
end

local cases = {
    {8, 4096, 200},
    {16, 4096, 200},
    {32, 4096, 120},
}

for _, entry in ipairs(cases) do
    local taps, n, iters = entry[1], entry[2], entry[3]
    local coeffs = make_coeffs(taps)
    local fir = make_fir(coeffs)

    local x = terralib.new(double[n])
    local y = terralib.new(double[n])
    local expect = terralib.new(double[n])
    fill(x, n)
    zero(y, n)
    zero(expect, n)

    local t0 = now_ms()
    fir(x, y, n)
    local first_ms = now_ms() - t0

    lua_fir(coeffs, x, expect, n)
    for i = 0, n - 1 do
        local diff = math.abs(y[i] - expect[i])
        assert(diff < 1e-9, string.format("terra fir mismatch at %d: got=%f expect=%f", i, y[i], expect[i]))
    end

    local t1 = now_ms()
    for _ = 1, iters do
        fir(x, y, n)
    end
    local run_ms = now_ms() - t1

    io.write(string.format("%d %d %.6f %.6f\n", taps, n, first_ms, run_ms))
end
