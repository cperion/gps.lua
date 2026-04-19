local function now_ms()
    return os.clock() * 1000.0
end

terra matmul(a: &double, b: &double, c: &double, M: int32, N: int32, K: int32)
    var i: int32 = 0
    while i < M do
        var j: int32 = 0
        while j < N do
            var k: int32 = 0
            var sum: double = 0.0
            while k < K do
                sum = sum + a[i * K + k] * b[k * N + j]
                k = k + 1
            end
            c[i * N + j] = sum
            j = j + 1
        end
        i = i + 1
    end
end

local function fill(ptr, n)
    for i = 0, n - 1 do
        ptr[i] = ((i * 13) % 17) * 0.25 - 2.0
    end
end

local function zero(ptr, n)
    for i = 0, n - 1 do
        ptr[i] = 0.0
    end
end

local function lua_matmul(a, b, c, M, N, K)
    for i = 0, M - 1 do
        for j = 0, N - 1 do
            local sum = 0.0
            for k = 0, K - 1 do
                sum = sum + a[i * K + k] * b[k * N + j]
            end
            c[i * N + j] = sum
        end
    end
end

local cases = {
    {16, 16, 16, 200},
    {32, 32, 32, 80},
    {64, 64, 64, 10},
}

for _, entry in ipairs(cases) do
    local M, N, K, iters = entry[1], entry[2], entry[3], entry[4]
    local a_elems = M * K
    local b_elems = K * N
    local c_elems = M * N

    local a = terralib.new(double[a_elems])
    local b = terralib.new(double[b_elems])
    local c = terralib.new(double[c_elems])
    local expect = terralib.new(double[c_elems])

    fill(a, a_elems)
    fill(b, b_elems)
    zero(c, c_elems)
    zero(expect, c_elems)

    local t0 = now_ms()
    matmul(a, b, c, M, N, K)
    local first_ms = now_ms() - t0

    lua_matmul(a, b, expect, M, N, K)
    for i = 0, c_elems - 1 do
        local diff = math.abs(c[i] - expect[i])
        assert(diff < 1e-9, string.format("terra matmul mismatch at %d: got=%f expect=%f", i, c[i], expect[i]))
    end

    local t1 = now_ms()
    for _ = 1, iters do
        matmul(a, b, c, M, N, K)
    end
    local run_ms = now_ms() - t1

    io.write(string.format("%d %d %d %.6f %.6f\n", M, N, K, first_ms, run_ms))
end
