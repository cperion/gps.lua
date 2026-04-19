local wj = require("watjit")

local function layout(sample_count, elem_size)
    elem_size = elem_size or 8
    local x_bytes = sample_count * elem_size
    local y_bytes = sample_count * elem_size
    return {
        x_offset = 0,
        y_offset = x_bytes,
        x_bytes = x_bytes,
        y_bytes = y_bytes,
        total_bytes = x_bytes + y_bytes,
        elem_size = elem_size,
        samples = sample_count,
    }
end

local function make(coeffs, T)
    assert(type(coeffs) == "table" and #coeffs > 0, "coeffs must be a non-empty array")
    T = T or wj.f64

    local i32 = wj.i32
    local taps = #coeffs
    local name = ("fir_%d_%s"):format(taps, T.name)

    return wj.fn {
        name = name,
        params = { i32 "x_base", i32 "y_base", i32 "n" },
        body = function(x_base, y_base, n)
            local x = wj.view(T, x_base, "x")
            local y = wj.view(T, y_base, "y")
            local i = wj.let(i32, "i")
            local acc = wj.let(T, "acc", 0)

            wj.for_(i, i32(taps - 1), n, function()
                acc(0)
                for j = 0, taps - 1 do
                    acc(acc + T(coeffs[j + 1]) * x[i - i32(j)])
                end
                y[i](acc)
            end)
        end,
    }
end

local function make_simd(coeffs, vector_t)
    assert(type(coeffs) == "table" and #coeffs > 0, "coeffs must be a non-empty array")
    vector_t = vector_t or wj.simd.f64x2

    local T = vector_t.lane_type
    local i32 = wj.i32
    local taps = #coeffs
    local lanes = vector_t.lanes
    local full_blocks = math.floor(taps / lanes)
    local rem = taps % lanes
    local coeff_vecs = {}

    for block = 0, full_blocks - 1 do
        local lanes_tbl = {}
        for lane = 0, lanes - 1 do
            local src = block * lanes + (lanes - 1 - lane)
            lanes_tbl[lane + 1] = coeffs[src + 1]
        end
        coeff_vecs[block + 1] = vector_t(lanes_tbl)
    end

    local name = ("fir_%d_%s_simd"):format(taps, vector_t.name)

    return wj.fn {
        name = name,
        params = { i32 "x_base", i32 "y_base", i32 "n" },
        body = function(x_base, y_base, n)
            local x = wj.view(T, x_base, "x")
            local y = wj.view(T, y_base, "y")
            local i = wj.let(i32, "i")
            local acc = wj.let(vector_t, "acc", vector_t.zero())

            wj.for_(i, i32(taps - 1), n, function()
                acc(vector_t.zero())
                for block = 0, full_blocks - 1 do
                    local start = block * lanes
                    local x_index = i - i32(start + (lanes - 1))
                    acc(acc + coeff_vecs[block + 1] * vector_t.load(x, x_index))
                end
                local out = wj.let(T, "out", vector_t.sum(acc))
                for j = full_blocks * lanes, full_blocks * lanes + rem - 1 do
                    out(out + T(coeffs[j + 1]) * x[i - i32(j)])
                end
                y[i](out)
            end)
        end,
    }
end

return {
    layout = layout,
    make = make,
    make_simd = make_simd,
}
