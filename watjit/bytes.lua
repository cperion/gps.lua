local types = require("watjit.types")
local ctrl = require("watjit.ctrl")
local funcmod = require("watjit.func")
local struct = require("watjit.struct")

local function bytes(name)
    assert(type(name) == "string", "bytes name must be a string")

    local i32 = types.i32
    local u8 = types.u8
    local u32 = types.u32

    local Slice = struct(name .. "_Slice", {
        { "ptr", i32 },
        { "len", i32 },
    }, {
        packed = false,
    })

    local Buf = struct(name .. "_Buf", {
        { "ptr", i32 },
        { "len", i32 },
        { "cap", i32 },
    }, {
        packed = false,
    })

    local eq_u8 = funcmod.fn {
        name = name .. "_bytes_eq_u8",
        params = { i32 "a_base", i32 "a_len", i32 "b_base", i32 "b_len" },
        ret = i32,
        body = function(a_base, a_len, b_base, b_len)
            local a = types.view(u8, a_base, "a")
            local b = types.view(u8, b_base, "b")
            local i = i32("i")
            local out = i32("out", 1)

            ctrl.if_(a_len:ne(b_len), function()
                out(0)
            end, function()
                ctrl.for_(i, a_len, function(loop)
                    ctrl.if_(a[i]:ne(b[i]), function()
                        out(0)
                        loop:break_()
                    end)
                end)
            end)
            return out
        end,
    }

    local cmp_u8 = funcmod.fn {
        name = name .. "_bytes_cmp_u8",
        params = { i32 "a_base", i32 "a_len", i32 "b_base", i32 "b_len" },
        ret = i32,
        body = function(a_base, a_len, b_base, b_len)
            local a = types.view(u8, a_base, "a")
            local b = types.view(u8, b_base, "b")
            local i = i32("i")
            local n = i32("n", types.select(a_len:lt(b_len), a_len, b_len))
            local out = i32("out", 0)

            ctrl.for_(i, n, function(loop)
                local av = u8("av", a[i])
                local bv = u8("bv", b[i])
                ctrl.if_(av:ne(bv), function()
                    out(types.select(av:lt_u(bv), i32(-1), i32(1)))
                    loop:break_()
                end)
            end)

            ctrl.if_(out:eq(0), function()
                ctrl.if_(a_len:lt(b_len), function()
                    out(-1)
                end, function()
                    ctrl.if_(a_len:gt(b_len), function()
                        out(1)
                    end)
                end)
            end)

            return out
        end,
    }

    local find_byte = funcmod.fn {
        name = name .. "_bytes_find_byte",
        params = { i32 "base", i32 "len", u8 "needle" },
        ret = i32,
        body = function(base, len, needle)
            local bytes_view = types.view(u8, base, "bytes")
            local i = i32("i")
            local out = i32("out", -1)

            ctrl.for_(i, len, function(loop)
                ctrl.if_(bytes_view[i]:eq(needle), function()
                    out(i)
                    loop:break_()
                end)
            end)
            return out
        end,
    }

    local cstr_len = funcmod.fn {
        name = name .. "_cstr_len",
        params = { i32 "base" },
        ret = i32,
        body = function(base)
            local bytes_view = types.view(u8, base, "bytes")
            local i = i32("i", 0)
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                ctrl.if_(bytes_view[i]:eq(0), function()
                    active(0)
                end, function()
                    i(i + 1)
                    loop:continue_()
                end)
            end)
            return i
        end,
    }

    local cstr_cmp = funcmod.fn {
        name = name .. "_cstr_cmp",
        params = { i32 "a_base", i32 "b_base" },
        ret = i32,
        body = function(a_base, b_base)
            local a = types.view(u8, a_base, "a")
            local b = types.view(u8, b_base, "b")
            local i = i32("i", 0)
            local out = i32("out", 0)
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                local av = u8("av", a[i])
                local bv = u8("bv", b[i])
                ctrl.if_(av:ne(bv), function()
                    out(types.select(av:lt_u(bv), i32(-1), i32(1)))
                    active(0)
                end, function()
                    ctrl.if_(av:eq(0), function()
                        active(0)
                    end, function()
                        i(i + 1)
                        loop:continue_()
                    end)
                end)
            end)
            return out
        end,
    }

    local bytes_hash_u8 = funcmod.fn {
        name = name .. "_bytes_hash_u8",
        params = { i32 "base", i32 "len" },
        ret = u32,
        body = function(base, len)
            local bytes_view = types.view(u8, base, "bytes")
            local i = i32("i")
            local h = u32("h", u32(2166136261))

            ctrl.for_(i, len, function()
                h(h:bxor(types.zext(u32, bytes_view[i])))
                h(h * u32(16777619))
            end)
            return h
        end,
    }

    local cstr_hash = funcmod.fn {
        name = name .. "_cstr_hash",
        params = { i32 "base" },
        ret = u32,
        body = function(base)
            local bytes_view = types.view(u8, base, "bytes")
            local i = i32("i", 0)
            local h = u32("h", u32(2166136261))
            local active = i32("active", 1)

            ctrl.while_(active:ne(0), function(loop)
                local b = u8("b", bytes_view[i])
                ctrl.if_(b:eq(0), function()
                    active(0)
                end, function()
                    h(h:bxor(types.zext(u32, b)))
                    h(h * u32(16777619))
                    i(i + 1)
                    loop:continue_()
                end)
            end)
            return h
        end,
    }

    local buf_clear = funcmod.fn {
        name = name .. "_buf_clear",
        params = { i32 "buf_base" },
        body = function(buf_base)
            local buf = Buf.at(buf_base)
            buf.len(0)
        end,
    }

    local buf_append_u8 = funcmod.fn {
        name = name .. "_buf_append_u8",
        params = { i32 "buf_base", u8 "value" },
        ret = i32,
        body = function(buf_base, value)
            local buf = Buf.at(buf_base)
            local out = i32("out", 0)
            ctrl.if_(buf.len:lt(buf.cap), function()
                local dst = types.view(u8, buf.ptr, "dst")
                dst[buf.len](value)
                buf.len(buf.len + 1)
                out(1)
            end)
            return out
        end,
    }

    local buf_append_slice_u8 = funcmod.fn {
        name = name .. "_buf_append_slice_u8",
        params = { i32 "buf_base", i32 "src_base", i32 "src_len" },
        ret = i32,
        body = function(buf_base, src_base, src_len)
            local buf = Buf.at(buf_base)
            local src = types.view(u8, src_base, "src")
            local i = i32("i")
            local out = i32("out", 0)
            local new_len = i32("new_len", buf.len + src_len)

            ctrl.if_(new_len:le(buf.cap), function()
                local dst = types.view(u8, buf.ptr, "dst")
                local start = i32("start", buf.len)
                ctrl.for_(i, src_len, function()
                    dst[start + i](src[i])
                end)
                buf.len(new_len)
                out(1)
            end)
            return out
        end,
    }

    local buf_append_cstr = funcmod.fn {
        name = name .. "_buf_append_cstr",
        params = { i32 "buf_base", i32 "src_base" },
        ret = i32,
        body = function(buf_base, src_base)
            local buf = Buf.at(buf_base)
            local src = types.view(u8, src_base, "src")
            local needed = i32("needed", 0)
            local i = i32("i", 0)
            local active = i32("active", 1)
            local out = i32("out", 0)

            ctrl.while_(active:ne(0), function(loop)
                ctrl.if_(src[i]:eq(0), function()
                    active(0)
                end, function()
                    needed(needed + 1)
                    i(i + 1)
                    loop:continue_()
                end)
            end)

            ctrl.if_((buf.len + needed):le(buf.cap), function()
                local dst = types.view(u8, buf.ptr, "dst")
                local start = i32("start", buf.len)
                local j = i32("j", 0)
                local active2 = i32("active2", 1)
                ctrl.while_(active2:ne(0), function(loop)
                    local b = u8("b", src[j])
                    ctrl.if_(b:eq(0), function()
                        active2(0)
                    end, function()
                        dst[start + j](b)
                        j(j + 1)
                        loop:continue_()
                    end)
                end)
                buf.len(buf.len + needed)
                out(1)
            end)
            return out
        end,
    }

    return {
        name = name,
        Slice = Slice,
        Buf = Buf,
        eq_u8 = eq_u8,
        cmp_u8 = cmp_u8,
        find_byte = find_byte,
        cstr_len = cstr_len,
        cstr_cmp = cstr_cmp,
        hash_u8 = bytes_hash_u8,
        cstr_hash = cstr_hash,
        buf_clear = buf_clear,
        buf_append_u8 = buf_append_u8,
        buf_append_slice_u8 = buf_append_slice_u8,
        buf_append_cstr = buf_append_cstr,
        funcs = function(self)
            return {
                self.eq_u8,
                self.cmp_u8,
                self.find_byte,
                self.cstr_len,
                self.cstr_cmp,
                self.hash_u8,
                self.cstr_hash,
                self.buf_clear,
                self.buf_append_u8,
                self.buf_append_slice_u8,
                self.buf_append_cstr,
            }
        end,
    }
end

return bytes
