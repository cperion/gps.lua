local ml = require('moonlift')
ml.use()
local ffi = require('ffi')

-- 1. phi-loop expression
local sum_range = code[[
func sum_range(n: i32) -> i32
    return loop i: i32 = 0, acc: i32 = 0 while i < n
    next
        i = i + 1
        acc = acc + i
    end -> acc
end
]]()
assert(sum_range(4) == 6)
print('sum_range(4) =', sum_range(4))

-- 2. domain-loop over range(stop)
local sum_domain = code[[
func sum_domain(n: i32) -> i32
    return loop i over range(n), acc: i32 = 0
    next
        acc = acc + i
    end -> acc
end
]]()
assert(sum_domain(4) == 6)
print('sum_domain(4) =', sum_domain(4))

-- 3. domain-loop over range(start, stop)
local sum_domain2 = code[[
func sum_domain2(a: i32, b: i32) -> i32
    return loop i over range(a, b), acc: i32 = 0
    next
        acc = acc + i
    end -> acc
end
]]()
assert(sum_domain2(3, 6) == 12)
print('sum_domain2(3,6) =', sum_domain2(3,6))

-- 4. statement loop over zip_eq(dst, src) on slices
local gain_mod = module[[
slice F32Slice = f32

func gain(dst: &F32Slice, src: &F32Slice, g: f32) -> void
    loop i over zip_eq(dst, src)
        dst[i] = src[i] * g
    end
end
]]
local gain_h = gain_mod().gain
local src = ffi.new('float[4]', { 1, 2, 3, 4 })
local dst = ffi.new('float[4]')
local src_hdr = ffi.new('uint64_t[2]')
local dst_hdr = ffi.new('uint64_t[2]')
src_hdr[0] = tonumber(ffi.cast('intptr_t', src)); src_hdr[1] = 4
dst_hdr[0] = tonumber(ffi.cast('intptr_t', dst)); dst_hdr[1] = 4
gain_h(tonumber(ffi.cast('intptr_t', dst_hdr)), tonumber(ffi.cast('intptr_t', src_hdr)), 0.5)
assert(math.abs(dst[0] - 0.5) < 1e-6)
assert(math.abs(dst[1] - 1.0) < 1e-6)
assert(math.abs(dst[2] - 1.5) < 1e-6)
assert(math.abs(dst[3] - 2.0) < 1e-6)
print('gain ok')

-- 5. carried state over domain
local one_pole_mod = module[[
slice F32Slice = f32

func one_pole(dst: &F32Slice, src: &F32Slice, a: f32, b: f32, z1: f32) -> f32
    return loop i over zip_eq(dst, src), y: f32 = z1
        let yn: f32 = a * y + b * src[i]
        dst[i] = yn
    next
        y = yn
    end -> y
end
]]
local one_pole_h = one_pole_mod().one_pole
local src2 = ffi.new('float[4]', { 1, 1, 1, 1 })
local dst2 = ffi.new('float[4]')
local src2_hdr = ffi.new('uint64_t[2]')
local dst2_hdr = ffi.new('uint64_t[2]')
src2_hdr[0] = tonumber(ffi.cast('intptr_t', src2)); src2_hdr[1] = 4
dst2_hdr[0] = tonumber(ffi.cast('intptr_t', dst2)); dst2_hdr[1] = 4
local zf = one_pole_h(tonumber(ffi.cast('intptr_t', dst2_hdr)), tonumber(ffi.cast('intptr_t', src2_hdr)), 0.5, 0.5, 0.0)
assert(math.abs(dst2[0] - 0.5) < 1e-6)
assert(math.abs(dst2[1] - 0.75) < 1e-6)
assert(math.abs(dst2[2] - 0.875) < 1e-6)
assert(math.abs(dst2[3] - 0.9375) < 1e-6)
assert(math.abs(zf - 0.9375) < 1e-6)
print('one_pole ok, zf =', zf)

print('\nnew loop syntax tests ok')
