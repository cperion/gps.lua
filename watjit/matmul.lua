local wj = require("watjit")

local function layout(M, N, K, elem_size)
    elem_size = elem_size or 8

    local a_bytes = M * K * elem_size
    local b_bytes = K * N * elem_size
    local c_bytes = M * N * elem_size

    return {
        a_offset = 0,
        b_offset = a_bytes,
        c_offset = a_bytes + b_bytes,
        a_bytes = a_bytes,
        b_bytes = b_bytes,
        c_bytes = c_bytes,
        total_bytes = a_bytes + b_bytes + c_bytes,
        elem_size = elem_size,
        a_elems = M * K,
        b_elems = K * N,
        c_elems = M * N,
    }
end

local function emit_runtime_k(a, b, sum, i, j, K, N, i32)
    local k = wj.let(i32, "k")
    wj.for_(k, i32(K), function()
        sum(sum + a[i * i32(K) + k] * b[k * i32(N) + j])
    end)
end

local function emit_unrolled_k(a, b, sum, a_row, j, K, N, i32)
    for k = 0, K - 1 do
        local bk = i32(k * N)
        sum(sum + a[a_row + i32(k)] * b[bk + j])
    end
end

local function make(M, N, K, T, opts)
    T = T or wj.f64
    opts = opts or {}

    local i32 = wj.i32
    local unroll_k = opts.unroll_k
    local unroll_k_threshold = opts.unroll_k_threshold or 16
    if unroll_k == nil then
        unroll_k = K <= unroll_k_threshold
    end

    local name = ("matmul_%dx%dx%d_%s%s"):format(M, N, K, T.name, unroll_k and "_uk" or "")

    return wj.fn {
        name = name,
        params = { i32 "a_base", i32 "b_base", i32 "c_base" },
        body = function(a_base, b_base, c_base)
            local a = wj.view(T, a_base, "a")
            local b = wj.view(T, b_base, "b")
            local c = wj.view(T, c_base, "c")

            local i, j = wj.lets(i32, "i", "j")
            local a_row = wj.let(i32, "a_row", 0)
            local c_row = wj.let(i32, "c_row", 0)
            local sum = wj.let(T, "sum", 0)

            wj.for_(i, i32(M), function()
                a_row(i * i32(K))
                c_row(i * i32(N))
                wj.for_(j, i32(N), function()
                    sum(0)
                    if unroll_k then
                        emit_unrolled_k(a, b, sum, a_row, j, K, N, i32)
                    else
                        emit_runtime_k(a, b, sum, i, j, K, N, i32)
                    end
                    c[c_row + j](sum)
                end)
            end)
        end,
    }
end

local function make_simd(M, N, K, vector_t, opts)
    vector_t = vector_t or wj.simd.f64x2
    opts = opts or {}

    local T = vector_t.lane_type
    local i32 = wj.i32
    local lanes = vector_t.lanes
    local vec_cols = N - (N % lanes)
    local unroll_k = opts.unroll_k
    local unroll_k_threshold = opts.unroll_k_threshold or 16
    if unroll_k == nil then
        unroll_k = K <= unroll_k_threshold
    end

    local name = ("matmul_%dx%dx%d_%s_simd%s"):format(M, N, K, vector_t.name, unroll_k and "_uk" or "")

    return wj.fn {
        name = name,
        params = { i32 "a_base", i32 "b_base", i32 "c_base" },
        body = function(a_base, b_base, c_base)
            local a = wj.view(T, a_base, "a")
            local b = wj.view(T, b_base, "b")
            local c = wj.view(T, c_base, "c")

            local i, j, k = wj.lets(i32, "i", "j", "k")
            local a_row = wj.let(i32, "a_row", 0)
            local c_row = wj.let(i32, "c_row", 0)
            local acc = wj.let(vector_t, "acc", vector_t.zero())
            local a_scalar = wj.let(T, "a_scalar", 0)
            local a_vec = wj.let(vector_t, "a_vec", vector_t.zero())
            local b_index = wj.let(i32, "b_index", 0)
            local sum = wj.let(T, "sum", 0)

            wj.for_(i, i32(M), function()
                a_row(i * i32(K))
                c_row(i * i32(N))

                wj.for_(j, i32(0), i32(vec_cols), i32(lanes), function()
                    acc(vector_t.zero())
                    if unroll_k then
                        for kk = 0, K - 1 do
                            a_scalar(a[a_row + i32(kk)])
                            a_vec(vector_t.splat(a_scalar))
                            b_index(i32(kk * N) + j)
                            acc(acc + a_vec * vector_t.load(b, b_index))
                        end
                    else
                        wj.for_(k, i32(K), function()
                            a_scalar(a[a_row + k])
                            a_vec(vector_t.splat(a_scalar))
                            b_index(k * i32(N) + j)
                            acc(acc + a_vec * vector_t.load(b, b_index))
                        end)
                    end
                    vector_t.store(c, c_row + j, acc)
                end)

                wj.for_(j, i32(vec_cols), i32(N), function()
                    sum(0)
                    if unroll_k then
                        emit_unrolled_k(a, b, sum, a_row, j, K, N, i32)
                    else
                        emit_runtime_k(a, b, sum, i, j, K, N, i32)
                    end
                    c[c_row + j](sum)
                end)
            end)
        end,
    }
end

return {
    layout = layout,
    make = make,
    make_simd = make_simd,
}
