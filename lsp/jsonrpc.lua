-- lsp/jsonrpc.lua
--
-- JSON-RPC 2.0 stdio loop for lsp.server.
--
-- Usage:
--   local Rpc = require("lsp.jsonrpc")
--   Rpc.run_stdio({ parse = ..., position_to_anchor = ..., adapter_opts = ... })

package.path = "./?.lua;./?/init.lua;" .. package.path

local ServerCore = require("lsp.server")

local M = {}

-- Explicit JSON null sentinel (so object keys can carry null values)
local JSON_NULL = {}

-- ══════════════════════════════════════════════════════════════
--  Minimal JSON codec (sufficient for JSON-RPC/LSP payloads)
-- ══════════════════════════════════════════════════════════════

local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false, 0
        end
        if k > n then n = k end
    end
    for i = 1, n do
        if t[i] == nil then return false, 0 end
    end
    return true, n
end

local ESC_MAP = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function encode_string(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(ch)
        local esc = ESC_MAP[ch]
        if esc then return esc end
        return string.format("\\u%04X", ch:byte())
    end) .. '"'
end

local function json_encode(v)
    if v == JSON_NULL then return "null" end
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            error("json encode: non-finite number")
        end
        return tostring(v)
    end
    if tv == "string" then return encode_string(v) end

    if tv == "table" then
        local arr, n = is_array(v)
        if arr then
            local parts = {}
            for i = 1, n do parts[i] = json_encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end

        local keys, k = {}, 0
        for key in pairs(v) do
            if type(key) ~= "string" then
                error("json encode: object keys must be strings")
            end
            k = k + 1
            keys[k] = key
        end
        table.sort(keys)

        local parts = {}
        for i = 1, #keys do
            local key = keys[i]
            parts[i] = encode_string(key) .. ":" .. json_encode(v[key])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    error("json encode: unsupported type " .. tv)
end

local function utf8_encode_cp(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(
            0xC0 + math.floor(cp / 0x40),
            0x80 + (cp % 0x40)
        )
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + math.floor(cp / 0x1000),
            0x80 + (math.floor(cp / 0x40) % 0x40),
            0x80 + (cp % 0x40)
        )
    end
    return string.char(
        0xF0 + math.floor(cp / 0x40000),
        0x80 + (math.floor(cp / 0x1000) % 0x40),
        0x80 + (math.floor(cp / 0x40) % 0x40),
        0x80 + (cp % 0x40)
    )
end

local function json_decode(s)
    local i, n = 1, #s

    local function err(msg)
        error("json decode error at " .. tostring(i) .. ": " .. msg)
    end

    local function skip_ws()
        while i <= n do
            local c = s:byte(i)
            if c == 32 or c == 9 or c == 10 or c == 13 then
                i = i + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        i = i + 1 -- opening quote
        local out = {}
        local o = 0

        while i <= n do
            local c = s:byte(i)
            if c == 34 then -- "
                i = i + 1
                return table.concat(out)
            elseif c == 92 then -- backslash
                local esc = s:byte(i + 1)
                if not esc then err("unfinished escape") end
                if esc == 34 then o = o + 1; out[o] = '"'; i = i + 2
                elseif esc == 92 then o = o + 1; out[o] = "\\"; i = i + 2
                elseif esc == 47 then o = o + 1; out[o] = "/"; i = i + 2
                elseif esc == 98 then o = o + 1; out[o] = "\b"; i = i + 2
                elseif esc == 102 then o = o + 1; out[o] = "\f"; i = i + 2
                elseif esc == 110 then o = o + 1; out[o] = "\n"; i = i + 2
                elseif esc == 114 then o = o + 1; out[o] = "\r"; i = i + 2
                elseif esc == 116 then o = o + 1; out[o] = "\t"; i = i + 2
                elseif esc == 117 then
                    local function hex4_at(pos)
                        local h = s:sub(pos, pos + 3)
                        if #h < 4 or not h:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
                            return nil
                        end
                        return tonumber(h, 16)
                    end

                    local cp = hex4_at(i + 2)
                    if not cp then err("invalid unicode escape") end

                    local consumed = 6
                    if cp >= 0xD800 and cp <= 0xDBFF then
                        -- High surrogate: expect a following low surrogate escape.
                        if s:byte(i + 6) == 92 and s:byte(i + 7) == 117 then
                            local cp2 = hex4_at(i + 8)
                            if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                                cp = 0x10000 + ((cp - 0xD800) * 0x400) + (cp2 - 0xDC00)
                                consumed = 12
                            else
                                cp = 0xFFFD
                            end
                        else
                            cp = 0xFFFD
                        end
                    elseif cp >= 0xDC00 and cp <= 0xDFFF then
                        -- Unpaired low surrogate.
                        cp = 0xFFFD
                    end

                    o = o + 1
                    out[o] = utf8_encode_cp(cp)
                    i = i + consumed
                else
                    err("invalid escape")
                end
            elseif c < 32 then
                err("control character in string")
            else
                o = o + 1
                out[o] = string.char(c)
                i = i + 1
            end
        end

        err("unterminated string")
    end

    local function parse_number()
        local start = i
        if s:byte(i) == 45 then i = i + 1 end

        local c = s:byte(i)
        if c == 48 then
            i = i + 1
        elseif c and c >= 49 and c <= 57 then
            i = i + 1
            while true do
                c = s:byte(i)
                if c and c >= 48 and c <= 57 then i = i + 1 else break end
            end
        else
            err("invalid number")
        end

        c = s:byte(i)
        if c == 46 then
            i = i + 1
            c = s:byte(i)
            if not (c and c >= 48 and c <= 57) then err("invalid fraction") end
            while true do
                c = s:byte(i)
                if c and c >= 48 and c <= 57 then i = i + 1 else break end
            end
        end

        c = s:byte(i)
        if c == 69 or c == 101 then
            i = i + 1
            c = s:byte(i)
            if c == 43 or c == 45 then i = i + 1 end
            c = s:byte(i)
            if not (c and c >= 48 and c <= 57) then err("invalid exponent") end
            while true do
                c = s:byte(i)
                if c and c >= 48 and c <= 57 then i = i + 1 else break end
            end
        end

        local num = tonumber(s:sub(start, i - 1))
        if num == nil then err("invalid number conversion") end
        return num
    end

    local function parse_array()
        i = i + 1 -- [
        skip_ws()
        local out = {}
        if s:byte(i) == 93 then i = i + 1; return out end

        local idx = 0
        while true do
            idx = idx + 1
            out[idx] = parse_value()
            skip_ws()
            local c = s:byte(i)
            if c == 44 then
                i = i + 1
                skip_ws()
            elseif c == 93 then
                i = i + 1
                return out
            else
                err("expected ',' or ']' in array")
            end
        end
    end

    local function parse_object()
        i = i + 1 -- {
        skip_ws()
        local out = {}
        if s:byte(i) == 125 then i = i + 1; return out end

        while true do
            if s:byte(i) ~= 34 then err("expected string key") end
            local key = parse_string()
            skip_ws()
            if s:byte(i) ~= 58 then err("expected ':'") end
            i = i + 1
            skip_ws()
            out[key] = parse_value()
            skip_ws()
            local c = s:byte(i)
            if c == 44 then
                i = i + 1
                skip_ws()
            elseif c == 125 then
                i = i + 1
                return out
            else
                err("expected ',' or '}' in object")
            end
        end
    end

    parse_value = function()
        skip_ws()
        local c = s:byte(i)
        if not c then err("unexpected end of input") end

        if c == 34 then return parse_string() end
        if c == 123 then return parse_object() end
        if c == 91 then return parse_array() end
        if c == 45 or (c >= 48 and c <= 57) then return parse_number() end

        if s:sub(i, i + 3) == "true" then i = i + 4; return true end
        if s:sub(i, i + 4) == "false" then i = i + 5; return false end
        if s:sub(i, i + 3) == "null" then i = i + 4; return JSON_NULL end

        err("unexpected token")
    end

    local v = parse_value()
    skip_ws()
    if i <= n then err("trailing data") end
    return v
end

-- ══════════════════════════════════════════════════════════════
--  Framing
-- ══════════════════════════════════════════════════════════════

local function read_message()
    local headers = {}

    while true do
        local line = io.read("*l")
        if line == nil then return nil end
        line = line:gsub("\r$", "")
        if line == "" then break end

        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then headers[k:lower()] = v end
    end

    local len = tonumber(headers["content-length"])
    if not len then
        return nil, "missing Content-Length"
    end

    local body = io.read(len)
    if not body or #body < len then
        return nil, "short body"
    end

    local ok, msg = pcall(json_decode, body)
    if not ok then
        return nil, "bad json: " .. tostring(msg)
    end

    return msg
end

local function write_message(obj)
    local body = json_encode(obj)
    io.write("Content-Length: ", tostring(#body), "\r\n\r\n", body)
    io.flush()
end

-- ══════════════════════════════════════════════════════════════
--  JSON-RPC engine (ASDL envelope IR)
-- ══════════════════════════════════════════════════════════════

local function rpc_id_from_lua(C, id)
    if id == nil then return nil end
    if type(id) == "number" then return C.RpcIdNumber(id) end
    if type(id) == "string" then return C.RpcIdString(id) end
    return C.RpcIdNull()
end

local function rpc_id_to_lua(id)
    if not id then return nil end
    local k = tostring(id):match("^Lua%.([%w_]+)")
    if k == "RpcIdNumber" then return id.value end
    if k == "RpcIdString" then return id.value end
    if k == "RpcIdNull" then return JSON_NULL end
    return nil
end

local function default_capabilities(C)
    return C.LspCapabilities(
        2,      -- text_document_sync (incremental)
        true,   -- hover_provider
        true,   -- definition_provider
        true,   -- references_provider
        true,   -- document_highlight_provider
        C.LspDiagnosticProviderInfo(false, true),
        true,   -- completion_provider
        true,   -- document_symbol_provider
        true,   -- rename_provider
        true,   -- signature_help_provider
        true,   -- workspace_symbol_provider
        true,   -- code_action_provider
        true,   -- semantic_tokens_provider
        true,   -- inlay_hint_provider
        true    -- formatting_provider
    )
end

local function default_server_info(C)
    return C.LspServerInfo("lua-lsp-pvm", "0.1.0")
end

local function capabilities_to_lua(c)
    return {
        textDocumentSync = {
            openClose = true,
            change = c.text_document_sync,
            save = { includeText = false },
        },
        hoverProvider = c.hover_provider,
        definitionProvider = c.definition_provider,
        declarationProvider = true,
        implementationProvider = true,
        typeDefinitionProvider = true,
        referencesProvider = c.references_provider,
        documentHighlightProvider = c.document_highlight_provider,
        diagnosticProvider = {
            interFileDependencies = c.diagnostic_provider.inter_file_dependencies,
            workspaceDiagnostics = c.diagnostic_provider.workspace_diagnostics,
        },
        completionProvider = c.completion_provider and {
            triggerCharacters = { ".", ":", "(", "'", "\"", "[", ",", "#", "*", "@", "|", "=", "-", "{", " ", "+", "?" },
            resolveProvider = true,
        } or nil,
        documentSymbolProvider = c.document_symbol_provider,
        renameProvider = c.rename_provider and { prepareProvider = true } or nil,
        signatureHelpProvider = c.signature_help_provider and { triggerCharacters = { "(", "," } } or nil,
        codeActionProvider = c.code_action_provider and {
            codeActionKinds = { "", "quickfix", "refactor.rewrite", "refactor.extract", "source" },
            resolveProvider = true,
        } or nil,
        semanticTokensProvider = c.semantic_tokens_provider and {
            legend = {
                tokenTypes = {
                    "namespace", "type", "class", "enum", "interface", "struct", "typeParameter",
                    "parameter", "variable", "property", "enumMember", "event", "function", "method",
                    "macro", "keyword", "modifier", "comment", "string", "number", "regexp", "operator", "decorator"
                },
                tokenModifiers = {
                    "declaration", "definition", "readonly", "static", "deprecated",
                    "abstract", "async", "modification", "documentation", "defaultLibrary", "global"
                },
            },
            full = true,
            range = true,
        } or nil,
        inlayHintProvider = c.inlay_hint_provider and { resolveProvider = false } or nil,
        documentFormattingProvider = c.formatting_provider,
        documentRangeFormattingProvider = c.formatting_provider,
        documentOnTypeFormattingProvider = c.formatting_provider and { firstTriggerCharacter = "\n" } or nil,
        foldingRangeProvider = true,
        selectionRangeProvider = true,
        codeLensProvider = { resolveProvider = false },
        colorProvider = true,
        executeCommandProvider = {
            commands = { "lua.removeSpace", "lua.solve", "lua.jsonToLua", "lua.setConfig", "lua.getConfig", "lua.autoRequire" },
        },
        workspaceSymbolProvider = c.workspace_symbol_provider,
        positionEncoding = "utf-16",
        offsetEncoding = "utf-16",
        workspace = {
            workspaceFolders = { supported = true, changeNotifications = true },
        },
    }
end

local function payload_to_lua(core, payload)
    local k = tostring(payload):match("^Lua%.([%w_]+)%(")
    if k == "PayloadNull" then return JSON_NULL end
    if k == "PayloadInitialize" then
        local v = payload.value
        return {
            capabilities = capabilities_to_lua(v.capabilities),
            serverInfo = { name = v.server_info.name, version = v.server_info.version },
        }
    end
    if k == "PayloadDiagnosticReport" then return core:to_lsp(payload.value) end
    if k == "PayloadHoverResult" then return core:to_lsp(payload.value) end
    if k == "PayloadLocationList" then return core:to_lsp(payload.value) end
    if k == "PayloadDocumentHighlightList" then return core:to_lsp(payload.value) end
    if k == "PayloadCompletionList" then return core:to_lsp(payload.value) end
    if k == "PayloadCompletionItem" then return core:to_lsp(payload.value) end
    if k == "PayloadDocumentSymbolList" then return core:to_lsp(payload.value) end
    if k == "PayloadSignatureHelp" then return core:to_lsp(payload.value) end
    if k == "PayloadWorkspaceEdit" then return core:to_lsp(payload.value) end
    if k == "PayloadRange" then return core:to_lsp(payload.value) end
    if k == "PayloadCodeActionList" then return core:to_lsp(payload.value) end
    if k == "PayloadCodeAction" then return core:to_lsp(payload.value) end
    if k == "PayloadSemanticTokens" then return core:to_lsp(payload.value) end
    if k == "PayloadInlayHintList" then return core:to_lsp(payload.value) end
    if k == "PayloadTextEditList" then return core:to_lsp(payload.value) end
    if k == "PayloadFoldingRangeList" then return core:to_lsp(payload.value) end
    if k == "PayloadSelectionRangeList" then return core:to_lsp(payload.value) end
    if k == "PayloadCodeLensList" then return core:to_lsp(payload.value) end
    if k == "PayloadColorInfoList" then return core:to_lsp(payload.value) end
    if k == "PayloadWorkspaceSymbolList" then return core:to_lsp(payload.value) end
    if k == "PayloadWorkspaceDiagnostic" then return core:to_lsp(payload.value) end
    if k == "PayloadExecuteResult" then return payload.value end
    if k == "PayloadPublishDiagnostics" then
        local d = core:to_lsp(payload.value)
        return { uri = d.uri, diagnostics = d.items or {}, version = d.version }
    end
    return JSON_NULL
end

local function outgoing_to_lua(core, out)
    local k = tostring(out):match("^Lua%.([%w_]+)%(")
    if k == "RpcOutNone" then return nil end
    if k == "RpcOutResult" then
        return {
            jsonrpc = "2.0",
            id = rpc_id_to_lua(out.id),
            result = payload_to_lua(core, out.payload),
        }
    end
    if k == "RpcOutError" then
        return {
            jsonrpc = "2.0",
            id = rpc_id_to_lua(out.id),
            error = {
                code = out.code,
                message = out.message,
                data = out.data ~= "" and out.data or nil,
            }
        }
    end
    if k == "RpcOutNotification" then
        return {
            jsonrpc = "2.0",
            method = out.method,
            params = payload_to_lua(core, out.payload),
        }
    end
    return nil
end

local function incoming_from_message(core, C, msg)
    local method_raw = msg and msg.method
    local method = (type(method_raw) == "string") and method_raw or nil
    local id = rpc_id_from_lua(C, msg and msg.id)

    local params = msg and msg.params
    if params == nil or params == JSON_NULL or type(params) ~= "table" then
        params = {}
    end

    -- Client->server responses (no method) are irrelevant here; ignore.
    if method_raw == nil then
        return C.RpcInIgnore("<response>")
    end

    if method == nil then
        local req = C.ReqInvalid("invalid method")
        if id then return C.RpcInLspRequest(id, req) end
        return C.RpcInInvalid("invalid method")
    end

    if method == "initialize" then
        return C.RpcInInitialize(id or C.RpcIdNull())
    end
    if method == "initialized" then return C.RpcInInitialized() end
    if method == "shutdown" then return C.RpcInShutdown(id or C.RpcIdNull()) end
    if method == "exit" then return C.RpcInExit() end
    if method and method:sub(1, 2) == "$/" then return C.RpcInIgnore(method) end

    local req = core:request_from_lsp(method, params)
    if req.kind == "ReqInvalid" then
        if id then return C.RpcInLspRequest(id, req) end
        return C.RpcInInvalid(req.reason)
    end

    if id then return C.RpcInLspRequest(id, req) end
    return C.RpcInLspNotification(req)
end

function M.new(opts)
    opts = opts or {}

    local self = {
        core = opts.core or ServerCore.new(opts),
        initialized = false,
        shutdown = false,
        publish_on_change = (opts.publish_on_change == true),
    }

    local C = self.core.engine.C
    self.capabilities = opts.capabilities_asdl or default_capabilities(C)
    self.server_info = opts.server_info_asdl or default_server_info(C)

    local function send(msg)
        write_message(msg)
    end

    local function maybe_publish(req)
        if not self.publish_on_change then return nil end
        if req.kind == "ReqDidOpen" or req.kind == "ReqDidChange" or req.kind == "ReqDidSave" then
            local d = self.core:diagnostic(C.ReqDiagnostic(C.LspDocIdentifier(req.doc.uri)))
            return C.RpcOutNotification("textDocument/publishDiagnostics", C.PayloadPublishDiagnostics(d))
        end
        if req.kind == "ReqDidClose" then
            local d = C.LspDiagnosticReport(C.DiagReportFull, {}, req.doc.uri, 0)
            return C.RpcOutNotification("textDocument/publishDiagnostics", C.PayloadPublishDiagnostics(d))
        end
        return nil
    end

    function self:handle_message(msg)
        local incoming = incoming_from_message(self.core, C, msg)
        local ik = tostring(incoming):match("^Lua%.([%w_]+)%(")

        if ik == "RpcInInitialize" then
            self.initialized = true
            local init = C.LspInitializeResult(self.capabilities, self.server_info)
            return outgoing_to_lua(self.core, C.RpcOutResult(incoming.id, C.PayloadInitialize(init)))
        end

        if ik == "RpcInInitialized" then
            return nil
        end

        if ik == "RpcInShutdown" then
            self.shutdown = true
            return outgoing_to_lua(self.core, C.RpcOutResult(incoming.id, C.PayloadNull()))
        end

        if ik == "RpcInExit" then
            os.exit(self.shutdown and 0 or 1)
        end

        if ik == "RpcInIgnore" then
            return nil
        end

        if ik == "RpcInInvalid" then
            return nil
        end

        if not self.initialized then
            if ik == "RpcInLspRequest" then
                return outgoing_to_lua(self.core, C.RpcOutError(incoming.id, -32002, "Server not initialized", ""))
            end
            return nil
        end

        if self.shutdown then
            if ik == "RpcInLspRequest" then
                -- Be lenient for clients that still send trailing requests between
                -- shutdown and exit; avoid noisy user-facing errors.
                return outgoing_to_lua(self.core, C.RpcOutResult(incoming.id, C.PayloadNull()))
            end
            return nil
        end

        local req = (ik == "RpcInLspRequest") and incoming.request or incoming.request
        local ok, result_or_err = pcall(function()
            return self.core:handle_request(req)
        end)

        if not ok then
            if ik ~= "RpcInLspRequest" then return nil end
            local emsg = tostring(result_or_err)
            local code, msg0
            if emsg:match("unsupported method") then
                code, msg0 = -32601, "Method not found"
            elseif emsg:match("invalid method") or emsg:match("invalid request") then
                code, msg0 = -32600, "Invalid Request"
            else
                code, msg0 = -32603, "Internal error"
            end
            return outgoing_to_lua(self.core, C.RpcOutError(incoming.id, code, msg0, emsg))
        end

        local pub = maybe_publish(req)
        if pub then
            local note = outgoing_to_lua(self.core, pub)
            if note then send(note) end
        end

        if ik ~= "RpcInLspRequest" then return nil end

        local rk = req.kind
        local payload = C.PayloadNull()
        if rk == "ReqHover" then
            payload = C.PayloadHoverResult(result_or_err)
        elseif rk == "ReqDefinition" or rk == "ReqDeclaration" or rk == "ReqImplementation"
            or rk == "ReqTypeDefinition" or rk == "ReqReferences" then
            payload = C.PayloadLocationList(result_or_err)
        elseif rk == "ReqDocumentHighlight" then
            payload = C.PayloadDocumentHighlightList(result_or_err)
        elseif rk == "ReqDiagnostic" then
            payload = C.PayloadDiagnosticReport(result_or_err)
        elseif rk == "ReqCompletion" then
            payload = C.PayloadCompletionList(result_or_err)
        elseif rk == "ReqCompletionResolve" then
            payload = C.PayloadCompletionItem(result_or_err)
        elseif rk == "ReqDocumentSymbol" then
            payload = C.PayloadDocumentSymbolList(result_or_err)
        elseif rk == "ReqSignatureHelp" then
            payload = C.PayloadSignatureHelp(result_or_err)
        elseif rk == "ReqRename" then
            if result_or_err and result_or_err.kind == "LspWorkspaceEdit" then
                payload = C.PayloadWorkspaceEdit(result_or_err)
            elseif result_or_err and result_or_err.kind == "RenameOk" then
                local edits = {}
                for i = 1, #result_or_err.edits do
                    edits[i] = C.LspTextEdit(result_or_err.edits[i].range, result_or_err.edits[i].new_text)
                end
                payload = C.PayloadWorkspaceEdit(C.LspWorkspaceEdit(edits, req.doc and req.doc.uri or ""))
            else
                payload = C.PayloadNull()
            end
        elseif rk == "ReqPrepareRename" then
            if result_or_err and result_or_err.kind == "LspRange" then
                payload = C.PayloadRange(result_or_err)
            else
                payload = C.PayloadNull()
            end
        elseif rk == "ReqCodeAction" then
            payload = C.PayloadCodeActionList(result_or_err)
        elseif rk == "ReqCodeActionResolve" then
            payload = C.PayloadCodeAction(result_or_err)
        elseif rk == "ReqSemanticTokensFull" or rk == "ReqSemanticTokensRange" then
            payload = C.PayloadSemanticTokens(result_or_err)
        elseif rk == "ReqInlayHint" then
            payload = C.PayloadInlayHintList(result_or_err)
        elseif rk == "ReqFormatting" then
            payload = C.PayloadTextEditList(result_or_err)
        elseif rk == "ReqFoldingRange" then
            payload = C.PayloadFoldingRangeList(result_or_err)
        elseif rk == "ReqSelectionRange" then
            payload = C.PayloadSelectionRangeList(result_or_err)
        elseif rk == "ReqCodeLens" then
            payload = C.PayloadCodeLensList(result_or_err)
        elseif rk == "ReqDocumentColor" then
            payload = C.PayloadColorInfoList(result_or_err)
        elseif rk == "ReqWorkspaceSymbol" then
            payload = C.PayloadWorkspaceSymbolList(result_or_err)
        elseif rk == "ReqWorkspaceDiagnostic" then
            payload = C.PayloadWorkspaceDiagnostic(result_or_err)
        elseif rk == "ReqExecuteCommand" then
            payload = C.PayloadExecuteResult(tostring(result_or_err or ""))
        end

        return outgoing_to_lua(self.core, C.RpcOutResult(incoming.id, payload))
    end

    function self:run_stdio()
        while true do
            local msg, rerr = read_message()
            if not msg then
                if rerr then
                    -- protocol-level issue without request id: cannot respond reliably.
                    -- just continue reading in case stream recovers.
                    -- (EOF returns nil,nil and breaks below)
                    if io.type(io.stdin) == "closed" then break end
                else
                    break
                end
            else
                if type(msg) ~= "table" then
                    -- ignore malformed top-level
                else
                    local resp = self:handle_message(msg)
                    if resp then send(resp) end
                end
            end
            if msg == nil and rerr == nil then break end
        end
    end

    return self
end

function M.run_stdio(opts)
    return M.new(opts):run_stdio()
end

-- Expose codec helpers for sibling tooling (parser adapters/tests).
M.JSON_NULL = JSON_NULL
M.json_encode = json_encode
M.json_decode = json_decode

return M
