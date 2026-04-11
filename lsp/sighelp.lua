-- lsp/sighelp.lua
--
-- Signature help: when typing function arguments, show param info.
-- pvm.lower("sig_help"): SignatureQuery → SignatureHelp

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(semantics_engine, type_engine)
    local C = semantics_engine.C

    local sig_help = pvm.lower("sig_help", function(q)
        -- For now: look up what's at position, if it's a call, find the function
        -- This is a stub that can be expanded with proper call-site analysis
        return C.SignatureHelp({}, 0)
    end)

    return {
        sig_help = sig_help,
        C = C,
    }
end

return M
