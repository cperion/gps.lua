-- json/format_asdl.lua
--
-- Flat formatting command vocabulary for pretty JSON execution.
--
-- Pretty-printing is modeled as:
--   Json.Value -> JsonFmt.Cmd* -> linear terminal
--
-- This keeps indentation relative and lets subtree formatting be reused without
-- baking absolute depth into cached strings.

local schema = require("json.asdl")

local M = {}
local T = schema.T
M.T = T

T:Define [[
    module JsonFmt {
        Kind = Text | Newline | PushIndent | PopIndent
        Cmd = (JsonFmt.Kind kind, string text) unique
    }
]]

M.K_TEXT = T.JsonFmt.Text
M.K_NEWLINE = T.JsonFmt.Newline
M.K_PUSH = T.JsonFmt.PushIndent
M.K_POP = T.JsonFmt.PopIndent

M.NL = T.JsonFmt.Cmd(M.K_NEWLINE, "")
M.PUSH = T.JsonFmt.Cmd(M.K_PUSH, "")
M.POP = T.JsonFmt.Cmd(M.K_POP, "")

function M.text(s)
    return T.JsonFmt.Cmd(M.K_TEXT, s)
end

return M
