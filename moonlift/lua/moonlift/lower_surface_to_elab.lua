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
    local lower_array_count_expr

    local function one_type(node, env)
        return pvm.one(lower_type(node, env))
    end

    local function lower_type_list(nodes, env)
        local out = {}
        for i = 1, #nodes do
            out[i] = one_type(nodes[i], env)
        end
        return out
    end

    local function find_type_entry(env, full_text)
        local types = env and env.types or nil
        if types == nil then return nil end
        for i = #types, 1, -1 do
            local entry = types[i]
            if entry.name == full_text then
                return entry.ty
            end
        end
        return nil
    end

    local function one_count_expr(node, env)
        return pvm.one(lower_array_count_expr(node, env))
    end

    lower_array_count_expr = pvm.phase("surface_to_elab_array_count_expr", {
        [Surf.SurfInt] = function(self)
            return pvm.once(Elab.ElabInt(self.raw, Elab.ElabTIndex))
        end,
        [Surf.SurfExprAdd] = function(self, env)
            return pvm.once(Elab.ElabExprAdd(Elab.ElabTIndex, one_count_expr(self.lhs, env), one_count_expr(self.rhs, env)))
        end,
        [Surf.SurfExprSub] = function(self, env)
            return pvm.once(Elab.ElabExprSub(Elab.ElabTIndex, one_count_expr(self.lhs, env), one_count_expr(self.rhs, env)))
        end,
        [Surf.SurfExprMul] = function(self, env)
            return pvm.once(Elab.ElabExprMul(Elab.ElabTIndex, one_count_expr(self.lhs, env), one_count_expr(self.rhs, env)))
        end,
    })

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
        [Surf.SurfTPtr] = function(self, env)
            return pvm.once(Elab.ElabTPtr(one_type(self.elem, env)))
        end,
        [Surf.SurfTSlice] = function(self, env)
            return pvm.once(Elab.ElabTSlice(one_type(self.elem, env)))
        end,
        [Surf.SurfTArray] = function(self, env)
            return pvm.once(Elab.ElabTArray(one_count_expr(self.count, env), one_type(self.elem, env)))
        end,
        [Surf.SurfTFunc] = function(self, env)
            return pvm.once(Elab.ElabTFunc(lower_type_list(self.params, env), one_type(self.result, env)))
        end,
        [Surf.SurfTNamed] = function(self, env)
            local parts = collect_name_parts(self.path)
            if #parts == 0 then
                error("surface_to_elab_type: empty named type path")
            end
            local full_text = table.concat(parts, ".")
            local ty = find_type_entry(env, full_text)
            if ty == nil then
                error("surface_to_elab_type: unknown named type '" .. full_text .. "'; provide it through ElabEnv.types")
            end
            return pvm.once(ty)
        end,
    })

    return {
        lower_type = lower_type,
    }
end

return M
