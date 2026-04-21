package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

local function collect_name_parts(path)
    local parts = {}
    local arr = path.parts
    for i = 1, #arr do
        parts[i] = arr[i].text
    end
    return parts
end

local function builtin_scalar(S, parts)
    if #parts ~= 1 then return nil end
    local n = parts[1]
    if n == "void" then return S.SemVoid end
    if n == "bool" then return S.SemBool end
    if n == "ptr" then return S.SemPtr end
    if n == "index" then return S.SemIndex end
    if n == "i8" then return S.SemInt(S.SemSigned, S.SemW8) end
    if n == "i16" then return S.SemInt(S.SemSigned, S.SemW16) end
    if n == "i32" then return S.SemInt(S.SemSigned, S.SemW32) end
    if n == "i64" then return S.SemInt(S.SemSigned, S.SemW64) end
    if n == "u8" then return S.SemInt(S.SemUnsigned, S.SemW8) end
    if n == "u16" then return S.SemInt(S.SemUnsigned, S.SemW16) end
    if n == "u32" then return S.SemInt(S.SemUnsigned, S.SemW32) end
    if n == "u64" then return S.SemInt(S.SemUnsigned, S.SemW64) end
    if n == "f32" then return S.SemFloat(S.SemF32) end
    if n == "f64" then return S.SemFloat(S.SemF64) end
    return nil
end

function M.Define(T)
    local Surf = T.MoonliftSurface
    local Sem = T.MoonliftSem

    local lower_type

    local function one_type(node)
        return pvm.one(lower_type(node))
    end

    local function lower_type_list(nodes)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_type(nodes[i])
        end
        return out
    end

    lower_type = pvm.phase("surface_to_sem_type", {
        [Surf.SurfTPath] = function(self)
            local parts = collect_name_parts(self.path)
            local scalar = builtin_scalar(Sem, parts)
            if scalar ~= nil then
                return pvm.once(Sem.SemTypeScalar(scalar))
            end

            if #parts == 0 then
                error("surface_to_sem_type: empty path")
            elseif #parts == 1 then
                return pvm.once(Sem.SemTypeNamed("", parts[1]))
            else
                local type_name = parts[#parts]
                parts[#parts] = nil
                return pvm.once(Sem.SemTypeNamed(table.concat(parts, "."), type_name))
            end
        end,

        [Surf.SurfTPtr] = function(self)
            return pvm.once(Sem.SemTypePtrTo(one_type(self.elem)))
        end,

        [Surf.SurfTSlice] = function(self)
            return pvm.once(Sem.SemTypeSlice(one_type(self.elem)))
        end,

        [Surf.SurfTArray] = function(self)
            local elem = one_type(self.elem)
            local count = self.count
            if count.kind == "SurfInt" then
                local n = tonumber(count.raw)
                if n == nil then
                    error("surface_to_sem_type: array count must be an integer literal")
                end
                return pvm.once(Sem.SemTypeArray(elem, n))
            end
            error("surface_to_sem_type: array count lowering currently requires an integer literal")
        end,

        [Surf.SurfTFunc] = function(self)
            return pvm.once(Sem.SemTypeFunc(
                lower_type_list(self.params),
                one_type(self.result)
            ))
        end,
    })

    return {
        lower_type = lower_type,
    }
end

return M
