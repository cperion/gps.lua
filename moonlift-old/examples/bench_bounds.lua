local ml = require('moonlift')
ml.use()
local ffi = require('ffi')

local backend = rawget(_G, '__moonlift_backend')
local debug = ml.debug

local function getenv_num(name, default)
    local v = os.getenv(name)
    if v == nil or v == '' then return default end
    local n = tonumber(v)
    return n or default
end

local function timeit(iters, fn)
    collectgarbage()
    collectgarbage()
    local out
    local t0 = os.clock()
    for _ = 1, iters do
        out = fn()
    end
    return os.clock() - t0, out
end

local function bench_pair(name, lua_fn, raw_handle, opt_handle, arg, iters)
    local raw_fn = function() return backend.call1(raw_handle, arg) end
    local opt_fn = function() return backend.call1(opt_handle, arg) end
    for _ = 1, 16 do
        lua_fn()
        raw_fn()
        opt_fn()
    end
    local lua_t, lua_out = timeit(iters, lua_fn)
    local raw_t, raw_out = timeit(iters, raw_fn)
    local opt_t, opt_out = timeit(iters, opt_fn)
    assert(lua_out == raw_out and raw_out == opt_out, name .. ' result mismatch')
    print(string.format(
        '%-18s lua=%8.3f ms  raw=%8.3f ms  opt=%8.3f ms  raw->opt=%5.2fx  out=%d',
        name,
        lua_t * 1000.0,
        raw_t * 1000.0,
        opt_t * 1000.0,
        raw_t / math.max(opt_t, 1e-12),
        opt_out
    ))
end

local function assert_hoistable(name, lowered)
    local raw_spec = assert(backend.dump_spec(lowered))
    local opt_spec = debug.dump_optimized_spec(lowered)
    assert(raw_spec:find('limit: Some(', 1, true) ~= nil, name .. ' raw spec lost checked indexing')
    assert(opt_spec:find('BoundsCheck {', 1, true) ~= nil, name .. ' optimized spec missing hoisted check')
    assert(opt_spec:find('limit: None', 1, true) ~= nil, name .. ' optimized spec kept in-loop bounds limit')
end

local N = math.max(4, getenv_num('MOONLIFT_BENCH_BOUNDS_N', 65536))
local ITERS = getenv_num('MOONLIFT_BENCH_BOUNDS_ITERS', 600)

local buf = ffi.new('int32_t[?]', N)
for i = 0, N - 1 do
    buf[i] = (i * 7 + 3) % 97
end

local buf_ptr = tonumber(ffi.cast('intptr_t', buf))
local slice_header = ffi.new('uint64_t[2]')
slice_header[0] = buf_ptr
slice_header[1] = N
local slice_ptr = tonumber(ffi.cast('intptr_t', slice_header))

local I32Slice = slice(i32)

local direct_builder = (func 'slice_sum_direct') {
    ptr(I32Slice)'s',
    function(s)
        return block(function()
            local acc = var(i32(0))
            for_range_(usize(0), s.len - usize(1), function(i)
                acc:set(acc + s[i])
            end)
            return acc
        end)
    end,
}

local affine_builder = (func 'slice_sum_affine2') {
    ptr(I32Slice)'s',
    function(s)
        return block(function()
            local acc = var(i32(0))
            for_range_(usize(0), s.len - usize(3), function(i)
                acc:set(acc + s[(i + usize(1)) + usize(1)])
            end)
            return acc
        end)
    end,
}

assert_hoistable('slice_sum_direct', direct_builder.lowered)
assert_hoistable('slice_sum_affine2', affine_builder.lowered)

local raw_direct = assert(backend.compile_unoptimized(direct_builder.lowered))
local opt_direct = assert(backend.compile(direct_builder.lowered))
local raw_affine = assert(backend.compile_unoptimized(affine_builder.lowered))
local opt_affine = assert(backend.compile(affine_builder.lowered))

local function lua_direct()
    local acc = 0
    for i = 0, N - 1 do
        acc = acc + buf[i]
    end
    return acc
end

local function lua_affine()
    local acc = 0
    for i = 2, N - 1 do
        acc = acc + buf[i]
    end
    return acc
end

print(string.format('moonlift bounds bench: n=%d iters=%d', N, ITERS))
print('')
print('BOUNDS-CHECK HOISTING')
bench_pair('slice_sum_direct', lua_direct, raw_direct, opt_direct, slice_ptr, ITERS)
bench_pair('slice_sum_affine2', lua_affine, raw_affine, opt_affine, slice_ptr, ITERS)
