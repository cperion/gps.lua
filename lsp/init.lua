-- lsp/init.lua
--
-- Public facade for the Lua LSP.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm        = require("pvm")
local ASDL       = require("lsp.asdl")
local Lexer      = require("lsp.lexer")
local Parser     = require("lsp.parser")
local Semantics  = require("lsp.semantics")
local TypeInfer  = require("lsp.typeinfer")
local Complete   = require("lsp.complete")
local DocSymbols = require("lsp.docsymbols")
local SigHelp    = require("lsp.sighelp")
local Rename     = require("lsp.rename")
local Format     = require("lsp.format")
local CodeAction = require("lsp.codeaction")
local SemTokens  = require("lsp.semtokens")
local Adapter    = require("lsp.adapter")
local Workspace  = require("lsp.workspace")
local Editor     = require("lsp.editor")
local Server     = require("lsp.server")
local JsonRpc    = require("lsp.jsonrpc")

local M = {}

function M.context()   return ASDL.context() end
function M.lexer(ctx)  return Lexer.new(ctx) end
function M.parser(ctx) return Parser.new(ctx) end
function M.semantics(ctx) return Semantics.new(ctx) end

function M.typeinfer(sem_engine)
    return TypeInfer.new(sem_engine)
end

function M.complete(sem_engine, type_engine)
    return Complete.new(sem_engine, type_engine)
end

function M.docsymbols(sem_engine)
    return DocSymbols.new(sem_engine)
end

function M.sighelp(sem_engine, type_engine)
    return SigHelp.new(sem_engine, type_engine)
end

function M.rename(sem_engine, adapter)
    return Rename.new(sem_engine, adapter)
end

function M.format(context)
    return Format.new(context)
end

function M.codeaction(context)
    return CodeAction.new(context)
end

function M.semtokens(sem_engine, lexer_engine, range_for)
    return SemTokens.new(sem_engine, lexer_engine, range_for)
end

function M.adapter(engine, opts)
    return Adapter.new(engine, opts)
end

function M.workspace(sem_engine, type_engine, opts)
    return Workspace.new(sem_engine, type_engine, opts)
end

function M.editor(context, opts)
    return Editor.new(context, opts)
end

--- Create a fully-wired LSP server with standalone parser + all features.
function M.server(opts)
    opts = opts or {}
    local ctx = opts.context or M.context()
    local C = ctx.Lua
    local parser_engine = M.parser(ctx)
    local lexer_engine = M.lexer(ctx)
    local sem = opts.engine or M.semantics(ctx)

    if not opts.parse then
        opts.parse = function(uri, version, text, prev_doc, _C, _params)
            return parser_engine.parse_incremental(uri, version or 0, text or "", prev_doc)
        end
    end

    if not opts.position_to_anchor then
        opts.position_to_anchor = function(doc, position)
            if not doc or not doc.anchors then return nil end
            local line = position.line or 0
            local ch = position.character or 0
            for i = 1, #doc.anchors do
                local p = doc.anchors[i]
                local rs, re = p.span.range.start, p.span.range.stop
                if (line > rs.line or (line == rs.line and ch >= rs.character))
                    and (line < re.line or (line == re.line and ch <= re.character)) then
                    return p.anchor
                end
            end
            return nil
        end
    end

    opts.context = ctx
    opts.engine = sem
    local core = Server.new(opts)

    -- Wire up extra engines
    local type_engine = M.typeinfer(sem)
    local complete_engine = M.complete(sem, type_engine)
    local docsymbols_engine = M.docsymbols(sem)
    local sighelp_engine = M.sighelp(sem, type_engine)
    local rename_engine = M.rename(sem, core.adapter)
    local format_engine = M.format(ctx)
    local codeaction_engine = M.codeaction(ctx)
    local semtokens_engine = M.semtokens(sem, lexer_engine, function(file, anchor)
        return core:_range_for(file, anchor)
    end)
    local workspace_engine = M.workspace(sem, type_engine, {
        range_for = function(file, anchor)
            return core:_range_for(file, anchor)
        end,
        lsp_diagnostic_report = function(file)
            return pvm.one(core.adapter:diagnostics(file))
        end,
    })
    local editor_engine = M.editor(ctx, {
        type_engine = type_engine,
        lexer_engine = lexer_engine,
        range_for = function(file, anchor)
            return core:_range_for(file, anchor)
        end,
        all_anchor_entries = function(file)
            return pvm.drain(core.adapter:all_anchor_entries(file))
        end,
    })

    -- Attach extra engines to core for request handling
    core._lexer_engine = lexer_engine
    core._type_engine = type_engine
    core._complete_engine = complete_engine
    core._docsymbols_engine = docsymbols_engine
    core._sighelp_engine = sighelp_engine
    core._rename_engine = rename_engine
    core._format_engine = format_engine
    core._codeaction_engine = codeaction_engine
    core._semtokens_engine = semtokens_engine
    core._workspace_engine = workspace_engine
    core._editor_engine = editor_engine

    return core
end

--- Run a full LSP server on stdio.
function M.run_stdio(opts)
    local server = M.server(opts)
    return JsonRpc.new({ core = server }):run_stdio()
end

-- Expose modules
M.ASDL = ASDL
M.Lexer = Lexer
M.Parser = Parser
M.Semantics = Semantics
M.TypeInfer = TypeInfer
M.Complete = Complete
M.DocSymbols = DocSymbols
M.SigHelp = SigHelp
M.Rename = Rename
M.Format = Format
M.CodeAction = CodeAction
M.SemTokens = SemTokens
M.Adapter = Adapter
M.Workspace = Workspace
M.Editor = Editor
M.Server = Server
M.JsonRpc = JsonRpc

return M
