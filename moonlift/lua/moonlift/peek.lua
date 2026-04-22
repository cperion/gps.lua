package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.Define(T, opts)
    local Sem = T.MoonliftSem

    local SurfaceToElabTop = require("moonlift.lower_surface_to_elab_top")
    local ElabToSem = require("moonlift.lower_elab_to_sem")
    local ResolveSemLayout = require("moonlift.resolve_sem_layout")
    local SemToBack = require("moonlift.lower_sem_to_back")
    local Jit = require("moonlift.jit")

    local s2e = SurfaceToElabTop.Define(T)
    local e2s = ElabToSem.Define(T)
    local resolve = ResolveSemLayout.Define(T)
    local s2b = SemToBack.Define(T)
    local jit_api = Jit.Define(T, opts)

    local function default_layout_env(layout_env)
        if layout_env ~= nil then
            return layout_env
        end
        return Sem.SemLayoutEnv({})
    end

    local function format_cmds(cmds)
        local lines = {}
        for i = 1, #cmds do
            lines[i] = string.format("%4d  %s", i, tostring(cmds[i]))
        end
        return table.concat(lines, "\n")
    end

    local function format_program(back_program)
        return format_cmds(back_program.cmds)
    end

    local PeekResult = {}
    PeekResult.__index = PeekResult

    function PeekResult:format_back()
        return format_program(self.back)
    end

    function PeekResult:require_disasm()
        if self.compile_error ~= nil then
            error(self.compile_error)
        end
        if self.disasm_error ~= nil then
            error(self.disasm_error)
        end
        return self.disasm
    end

    function PeekResult:free()
        if self.artifact ~= nil and self.artifact.free ~= nil then
            self.artifact:free()
            self.artifact = nil
        end
        if self._own_jit and self.jit ~= nil and self.jit.free ~= nil then
            self.jit:free()
            self.jit = nil
        end
    end

    local function lower_surface_module(surface_module, lower_opts)
        local layout_env = default_layout_env(lower_opts and lower_opts.layout_env or nil)
        local elab = pvm.one(s2e.lower_module(surface_module))
        local sem = pvm.one(e2s.lower_module(elab))
        local resolved = pvm.one(resolve.resolve_module(sem, layout_env))
        local back = pvm.one(s2b.lower_module(resolved, layout_env))
        return {
            surface = surface_module,
            elab = elab,
            sem = sem,
            resolved = resolved,
            back = back,
            layout_env = layout_env,
        }
    end

    local function peek_back_program(back_program, func, peek_opts)
        local jit = peek_opts and peek_opts.jit or jit_api.jit()
        local own_jit = peek_opts == nil or peek_opts.jit == nil
        local artifact = jit:compile(back_program)
        local disasm, bin_path = artifact:disasm(func, peek_opts)
        return setmetatable({
            back = back_program,
            func = func,
            jit = jit,
            artifact = artifact,
            disasm = disasm,
            bin_path = bin_path,
            _own_jit = own_jit,
        }, PeekResult)
    end

    local function peek_surface_module(surface_module, func, peek_opts)
        local stages = lower_surface_module(surface_module, peek_opts)
        local out = setmetatable({
            surface = stages.surface,
            elab = stages.elab,
            sem = stages.sem,
            resolved = stages.resolved,
            back = stages.back,
            layout_env = stages.layout_env,
            func = func,
        }, PeekResult)

        out.jit = peek_opts and peek_opts.jit or jit_api.jit()
        out._own_jit = peek_opts == nil or peek_opts.jit == nil

        local ok_compile, artifact_or_err = pcall(function()
            return out.jit:compile(stages.back)
        end)
        if not ok_compile then
            out.compile_error = artifact_or_err
            return out
        end
        out.artifact = artifact_or_err

        local ok_disasm, disasm_or_err, bin_path = pcall(function()
            local disasm, path = out.artifact:disasm(func, peek_opts)
            return disasm, path
        end)
        if ok_disasm then
            out.disasm = disasm_or_err
            out.bin_path = bin_path
        else
            out.disasm_error = disasm_or_err
        end

        return out
    end

    local function disasm_surface_module(surface_module, func, peek_opts)
        return peek_surface_module(surface_module, func, peek_opts)
    end

    local function hex_surface_module(surface_module, func, peek_opts)
        local result = peek_surface_module(surface_module, func, peek_opts)
        if result.compile_error ~= nil or result.disasm_error ~= nil then
            return result
        end
        result.hex = result.artifact:hexbytes(func, peek_opts and peek_opts.bytes or nil, peek_opts and peek_opts.cols or nil)
        return result
    end

    return {
        jit = jit_api.jit,
        lower_surface_module = lower_surface_module,
        format_cmds = format_cmds,
        format_program = format_program,
        format_back_program = format_program,
        peek_back_program = peek_back_program,
        peek_surface_module = peek_surface_module,
        disasm_surface_module = disasm_surface_module,
        hex_surface_module = hex_surface_module,
    }
end

return M
