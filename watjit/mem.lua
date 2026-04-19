local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local funcmod = require("watjit.func")

local function mem(name)
    assert(type(name) == "string", "mem name must be a string")

    local i32 = types.i32
    local u8 = types.u8

    local memcpy_u8 = funcmod.fn {
        name = name .. "_memcpy_u8",
        params = { i32 "dst_base", i32 "src_base", i32 "n" },
        ret = i32,
        body = function(dst_base, src_base, n)
            local dst = types.view(u8, dst_base, "dst")
            local src = types.view(u8, src_base, "src")
            local i = i32("i")

            ctrl.for_(i, n, function()
                dst[i](src[i])
            end)
            return dst_base
        end,
    }

    local memset_u8 = funcmod.fn {
        name = name .. "_memset_u8",
        params = { i32 "dst_base", u8 "value", i32 "n" },
        ret = i32,
        body = function(dst_base, value, n)
            local dst = types.view(u8, dst_base, "dst")
            local i = i32("i")

            ctrl.for_(i, n, function()
                dst[i](value)
            end)
            return dst_base
        end,
    }

    local memmove_u8 = funcmod.fn {
        name = name .. "_memmove_u8",
        params = { i32 "dst_base", i32 "src_base", i32 "n" },
        ret = i32,
        body = function(dst_base, src_base, n)
            local dst = types.view(u8, dst_base, "dst")
            local src = types.view(u8, src_base, "src")
            local i = i32("i")

            ctrl.if_(dst_base:lt(src_base), function()
                ctrl.for_(i, n, function()
                    dst[i](src[i])
                end)
            end, function()
                ctrl.if_(dst_base:ge(src_base + n), function()
                    ctrl.for_(i, n, function()
                        dst[i](src[i])
                    end)
                end, function()
                    i(n)
                    ctrl.while_(i:gt(0), function()
                        i(i - 1)
                        dst[i](src[i])
                    end)
                end)
            end)
            return dst_base
        end,
    }

    local memcmp_u8 = funcmod.fn {
        name = name .. "_memcmp_u8",
        params = { i32 "lhs_base", i32 "rhs_base", i32 "n" },
        ret = i32,
        body = function(lhs_base, rhs_base, n)
            local lhs = types.view(u8, lhs_base, "lhs")
            local rhs = types.view(u8, rhs_base, "rhs")
            local i = i32("i")
            local out = i32("out", 0)

            ctrl.for_(i, n, function(loop)
                local a = u8("a", lhs[i])
                local b = u8("b", rhs[i])
                ctrl.if_(a:ne(b), function()
                    out(types.select(a:lt_u(b), i32(-1), i32(1)))
                    loop:break_()
                end)
            end)
            return out
        end,
    }

    return {
        name = name,
        memcpy_u8 = memcpy_u8,
        memset_u8 = memset_u8,
        memmove_u8 = memmove_u8,
        memcmp_u8 = memcmp_u8,
        funcs = function(self)
            return {
                self.memcpy_u8,
                self.memset_u8,
                self.memmove_u8,
                self.memcmp_u8,
            }
        end,
    }
end

return mem
