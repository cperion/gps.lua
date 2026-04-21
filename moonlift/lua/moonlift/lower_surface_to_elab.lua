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

function M.Define(T)
    local Surf = T.MoonliftSurface
    local Elab = T.MoonliftElab

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

    lower_type = pvm.phase("surface_to_elab_type", {
        [Surf.SurfTVoid] = function()
            return pvm.once(Elab.ElabTVoid)
        end,
        [Surf.SurfTBool] = function()
            return pvm.once(Elab.ElabTBool)
        end,
        [Surf.SurfTI8] = function()
            return pvm.once(Elab.ElabTI8)
        end,
        [Surf.SurfTI16] = function()
            return pvm.once(Elab.ElabTI16)
        end,
        [Surf.SurfTI32] = function()
            return pvm.once(Elab.ElabTI32)
        end,
        [Surf.SurfTI64] = function()
            return pvm.once(Elab.ElabTI64)
        end,
        [Surf.SurfTU8] = function()
            return pvm.once(Elab.ElabTU8)
        end,
        [Surf.SurfTU16] = function()
            return pvm.once(Elab.ElabTU16)
        end,
        [Surf.SurfTU32] = function()
            return pvm.once(Elab.ElabTU32)
        end,
        [Surf.SurfTU64] = function()
            return pvm.once(Elab.ElabTU64)
        end,
        [Surf.SurfTF32] = function()
            return pvm.once(Elab.ElabTF32)
        end,
        [Surf.SurfTF64] = function()
            return pvm.once(Elab.ElabTF64)
        end,
        [Surf.SurfTIndex] = function()
            return pvm.once(Elab.ElabTIndex)
        end,
        [Surf.SurfTPtr] = function(self)
            return pvm.once(Elab.ElabTPtr(one_type(self.elem)))
        end,
        [Surf.SurfTSlice] = function(self)
            return pvm.once(Elab.ElabTSlice(one_type(self.elem)))
        end,
        [Surf.SurfTArray] = function(self)
            error("surface_to_elab_type: SurfTArray needs expression elaboration for count")
        end,
        [Surf.SurfTFunc] = function(self)
            return pvm.once(Elab.ElabTFunc(lower_type_list(self.params), one_type(self.result)))
        end,
        [Surf.SurfTNamed] = function(self)
            local parts = collect_name_parts(self.path)
            if #parts == 0 then
                error("surface_to_elab_type: empty named type path")
            elseif #parts == 1 then
                return pvm.once(Elab.ElabTNamed("", parts[1]))
            else
                local type_name = parts[#parts]
                parts[#parts] = nil
                return pvm.once(Elab.ElabTNamed(table.concat(parts, "."), type_name))
            end
        end,
    })

    return {
        lower_type = lower_type,
    }
end

return M
