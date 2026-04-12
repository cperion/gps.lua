-- lsp/codeaction.lua
--
-- Code action planner boundary.
-- pvm.lower("plan_code_actions"): CodeActionQuery -> LspCodeActionList

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

local function pos_leq(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.character <= b.character
end

local function range_intersects(a, b)
    if not a or not b or not a.start or not a.stop or not b.start or not b.stop then return false end
    return pos_leq(a.start, b.stop) and pos_leq(b.start, a.stop)
end

function M.new(context)
    local C = context.Lua

    local plan_code_actions = pvm.lower("plan_code_actions", function(q)
        local out = {}
        local seen = {}

        local function add(title, kind, edits, key)
            local k = key or title
            if seen[k] then return end
            seen[k] = true
            out[#out + 1] = C.LspCodeAction(title, kind, C.LspWorkspaceEdit(edits, q.uri))
        end

        for i = 1, #q.diagnostics do
            local d = q.diagnostics[i]
            if range_intersects(d.range, q.range) then
                local range_key = (d.range.start.line or 0) .. ":" .. (d.range.start.character or 0)

                if d.code == "undefined-global" then
                    local name = d.message:match("'([^']+)'")
                    if name and name:match("^[%a_][%w_]*$") then
                        add(
                            "Create local '" .. name .. "'",
                            C.CodeActionQuickFix,
                            { C.LspTextEdit(C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0)), "local " .. name .. " = nil\n") },
                            "mk-local:" .. name
                        )
                        add(
                            "Import module '" .. name .. "'",
                            C.CodeActionQuickFix,
                            { C.LspTextEdit(C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0)), "local " .. name .. " = require(\"" .. name .. "\")\n") },
                            "import-module:" .. name
                        )
                    end

                elseif d.code == "unused-local" or d.code == "unused-param" then
                    add(
                        "Rename to '_'",
                        C.CodeActionQuickFix,
                        { C.LspTextEdit(d.range, "_") },
                        "unused-to-underscore:" .. range_key
                    )

                elseif d.code == "unknown-type" then
                    local name = d.message:match("'([^']+)'")
                    if name and name:match("^[%a_][%w_]*$") then
                        add(
                            "Declare @class '" .. name .. "'",
                            C.CodeActionQuickFix,
                            { C.LspTextEdit(C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0)), "---@class " .. name .. "\n") },
                            "declare-class:" .. name
                        )
                    end
                end
            end
        end

        return C.LspCodeActionList(out)
    end)

    return {
        plan_code_actions = plan_code_actions,
        C = C,
    }
end

return M
