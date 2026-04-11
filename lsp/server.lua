-- lsp/server.lua
--
-- LSP server core with ASDL-typed request/state/response IR.
-- Parser-agnostic: you can plug in any parse(uri, text, prev, C, params) callback,
-- or use the built-in standalone parser.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Semantics = require("lsp.semantics")
local AdapterMod = require("lsp.adapter")

local Core = {}
Core.__index = Core

local function uri_from_params(params)
    if not params then return nil end
    if params.uri then return params.uri end
    if params.textDocument and params.textDocument.uri then return params.textDocument.uri end
    return nil
end

local function version_from_params(params)
    if not params then return nil end
    if params.version ~= nil then return params.version end
    if params.textDocument and params.textDocument.version ~= nil then return params.textDocument.version end
    return nil
end

local function text_from_params(params)
    if not params then return nil end
    if params.text then return params.text end
    if params.textDocument and params.textDocument.text then return params.textDocument.text end
    local changes = params.contentChanges
    if type(changes) == "table" and #changes > 0 then
        local last = changes[#changes]
        if last and last.text ~= nil then return last.text end
    end
    return nil
end

local function anchor_ref(C, v)
    if not v then return nil end
    if type(v) == "table" and tostring(v):match("^Lua%.AnchorRef%(") then return v end
    return C.AnchorRef(tostring(v))
end

function Core.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Core)
    self.engine = opts.engine or Semantics.new(opts.context)
    self.parse = opts.parse
    self.position_to_anchor = opts.position_to_anchor

    local C = self.engine.C
    self.docs = C.ServerDocStore({})

    if opts.adapter then
        self.adapter = opts.adapter
    else
        local aopts = opts.adapter_opts or {}
        if not aopts.meta_for_file then
            aopts.meta_for_file = function(file) return self:_meta_for_file(file) end
        end
        self.adapter = AdapterMod.new(self.engine, aopts)
    end

    self._doc_lookup = pvm.lower("core_doc_lookup", function(q)
        local docs = q.store.docs
        for i = 1, #docs do
            if docs[i].uri == q.uri then return C.ServerDocHit(docs[i]) end
        end
        return C.ServerDocMiss()
    end)

    return self
end

function Core:_meta_to_asdl(file, meta)
    local C = self.engine.C
    if type(meta) == "table" and tostring(meta):match("^Lua%.ServerMeta%(") then return meta end

    local positions, parse_error = {}, ""
    if type(meta) == "table" then
        local ps = meta.positions or {}
        for i = 1, #ps do
            local p = ps[i]
            positions[#positions + 1] = C.ServerAnchorPoint(
                anchor_ref(C, p.anchor or file),
                type(p.range) == "table" and tostring(p.range):match("^Lua%.LspRange%(") and p.range
                    or C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)),
                tostring(p.label or ""))
        end
        if meta.parse_error then parse_error = tostring(meta.parse_error) end
    elseif meta ~= nil then
        parse_error = tostring(meta)
    end
    return C.ServerMeta(positions, parse_error)
end

function Core:_set_doc(uri, version, text, file, meta)
    local C = self.engine.C
    local next_doc = C.ServerDoc(uri, version or 0, text or "", file, self:_meta_to_asdl(file, meta))
    local old = self.docs.docs
    local out, replaced = {}, false
    for i = 1, #old do
        if old[i].uri == uri then out[#out + 1] = next_doc; replaced = true
        else out[#out + 1] = old[i] end
    end
    if not replaced then out[#out + 1] = next_doc end
    self.docs = C.ServerDocStore(out)
    return next_doc
end

function Core:_doc(uri)
    local C = self.engine.C
    local hit = self._doc_lookup(C.ServerDocQuery(self.docs, uri))
    if hit.kind == "ServerDocHit" then return hit.doc end
    return nil
end

function Core:_meta_for_file(file)
    local docs = self.docs.docs
    for i = 1, #docs do if docs[i].file == file then return docs[i].meta end end
    return nil
end

function Core:_parse(uri, text, prev_file, version, params)
    if not self.parse then
        error("lsp/server: parse callback required", 2)
    end
    local parse_params = params
    if not (type(parse_params) == "table" and not tostring(parse_params):match("^Lua%.")) then
        parse_params = {
            uri = uri, version = version, text = text,
            textDocument = { uri = uri, version = version, text = text },
        }
    end
    local file, meta = self.parse(uri, text, prev_file, self.engine.C, parse_params)
    if not file then error("lsp/server: parse callback returned nil file", 2) end
    return file, meta
end

function Core:request_from_lsp(method, params)
    local C = self.engine.C
    params = params or {}
    local uri = uri_from_params(params) or ""
    local pos0 = params.position or (params.textDocumentPositionParams and params.textDocumentPositionParams.position) or {}
    local pos = C.LspPos(pos0.line or 0, pos0.character or 0)

    local subject = C.QueryMissing()
    if params.anchor then
        subject = C.QueryAnchor(anchor_ref(C, params.anchor))
    elseif params.typeName then
        subject = C.QueryTypeName(params.typeName)
    end

    if method == "textDocument/didOpen" then
        return C.ReqDidOpen(C.LspDocItem(uri, version_from_params(params) or 0, text_from_params(params) or ""))
    end
    if method == "textDocument/didChange" then
        local changes = {}
        local raw = params.contentChanges
        if type(raw) == "table" then
            for i = 1, #raw do changes[#changes + 1] = C.LspTextChange(tostring(raw[i] and raw[i].text or "")) end
        end
        if #changes == 0 then
            local t = text_from_params(params)
            if t ~= nil then changes[1] = C.LspTextChange(t) end
        end
        return C.ReqDidChange(C.LspVersionedDoc(uri, version_from_params(params) or 0), changes)
    end
    if method == "textDocument/didClose" then return C.ReqDidClose(C.LspDocIdentifier(uri)) end
    if method == "textDocument/hover" then return C.ReqHover(C.LspDocIdentifier(uri), pos, subject) end
    if method == "textDocument/definition" then return C.ReqDefinition(C.LspDocIdentifier(uri), pos, subject) end
    if method == "textDocument/references" then
        local incl = (params.context and params.context.includeDeclaration) and true
            or (params.includeDeclaration and true or false)
        return C.ReqReferences(C.LspDocIdentifier(uri), pos, subject, C.LspReferenceContext(incl))
    end
    if method == "textDocument/documentHighlight" then
        return C.ReqDocumentHighlight(C.LspDocIdentifier(uri), pos, subject)
    end
    if method == "textDocument/diagnostic" then return C.ReqDiagnostic(C.LspDocIdentifier(uri)) end
    if method == "textDocument/completion" then
        return C.ReqCompletion(C.LspDocIdentifier(uri), pos)
    end
    if method == "textDocument/documentSymbol" then
        return C.ReqDocumentSymbol(C.LspDocIdentifier(uri))
    end
    if method == "textDocument/signatureHelp" then
        return C.ReqSignatureHelp(C.LspDocIdentifier(uri), pos)
    end
    if method == "textDocument/rename" then
        return C.ReqRename(C.LspDocIdentifier(uri), pos, params.newName or "")
    end
    if method == "textDocument/prepareRename" then
        return C.ReqPrepareRename(C.LspDocIdentifier(uri), pos)
    end
    return C.ReqInvalid("unsupported method: " .. tostring(method))
end

function Core:_resolve_subject(doc, req, prefer_kind)
    local C = self.engine.C
    if not doc or not doc.file then return nil end
    local subject = req.subject or C.QueryMissing()
    if subject.kind == "QueryTypeName" then return subject.name end
    if subject.kind == "QueryAnchor" then return subject.anchor end
    local pos = req.position
    if not pos then return nil end
    local position = { line = pos.line, character = pos.character }
    if self.position_to_anchor then
        local ok, anchor = pcall(self.position_to_anchor, doc.file, position, doc, self.adapter, req)
        if ok and anchor then return anchor_ref(C, anchor) end
    end
    local pick = self.adapter:anchor_at_position(doc.file, position, prefer_kind)
    if pick and pick.kind == "AnchorPickHit" then return pick.anchor end
    return nil
end

function Core:did_open(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDidOpen") and arg or self:request_from_lsp("textDocument/didOpen", arg)
    if req.kind ~= "ReqDidOpen" then error("did_open: invalid request", 2) end
    local raw = (type(arg) == "table" and not tostring(arg):match("^Lua%.")) and arg or nil
    local file, meta = raw and raw.file or nil, raw and raw.meta or nil
    if not file then
        file, meta = self:_parse(req.doc.uri, req.doc.text or "", nil, req.doc.version or 0, raw or req)
    end
    return self:_set_doc(req.doc.uri, req.doc.version or 0, req.doc.text or "", file, meta)
end

function Core:did_change(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDidChange") and arg or self:request_from_lsp("textDocument/didChange", arg)
    if req.kind ~= "ReqDidChange" then error("did_change: invalid request", 2) end
    local uri = req.doc.uri
    local doc = self:_doc(uri)
    if not doc then error("did_change: unknown uri " .. tostring(uri), 2) end
    local raw = (type(arg) == "table" and not tostring(arg):match("^Lua%.")) and arg or nil
    local file, meta = raw and raw.file or nil, raw and raw.meta or nil
    local next_text = doc.text or ""
    if #req.changes > 0 then next_text = req.changes[#req.changes].text end
    if not file then
        file, meta = self:_parse(uri, next_text, doc.file, req.doc.version or doc.version or 0, raw or req)
    end
    return self:_set_doc(uri, req.doc.version or doc.version, next_text, file, meta)
end

function Core:did_close(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDidClose") and arg or self:request_from_lsp("textDocument/didClose", arg)
    if req.kind ~= "ReqDidClose" then error("did_close: invalid request", 2) end
    local old = self.docs.docs
    local out = {}
    for i = 1, #old do if old[i].uri ~= req.doc.uri then out[#out + 1] = old[i] end end
    self.docs = C.ServerDocStore(out)
    return true
end

function Core:diagnostic(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDiagnostic") and arg or self:request_from_lsp("textDocument/diagnostic", arg)
    if req.kind ~= "ReqDiagnostic" then error("diagnostic: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspDiagnosticReport("full", {}, req.doc.uri or "", 0) end
    local items = {}
    local ds = self.adapter:diagnostics(doc.file).items
    for i = 1, #ds do items[i] = ds[i] end
    if doc.meta and doc.meta.parse_error and doc.meta.parse_error ~= "" then
        items[#items + 1] = C.LspDiagnostic(
            C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)), 1,
            "lua-lsp-pvm", "parse-error", tostring(doc.meta.parse_error))
    end
    return C.LspDiagnosticReport("full", items, doc.uri, doc.version or 0)
end

function Core:hover(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqHover") and arg or self:request_from_lsp("textDocument/hover", arg)
    if req.kind ~= "ReqHover" then error("hover: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspHoverMiss() end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return C.LspHoverMiss() end
    return self.adapter:hover(doc.file, subject)
end

function Core:definition(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDefinition") and arg or self:request_from_lsp("textDocument/definition", arg)
    if req.kind ~= "ReqDefinition" then error("definition: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return C.LspLocationList({}) end
    return self.adapter:definition(doc.file, subject)
end

function Core:references(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqReferences") and arg or self:request_from_lsp("textDocument/references", arg)
    if req.kind ~= "ReqReferences" then error("references: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return C.LspLocationList({}) end
    return self.adapter:references(doc.file, subject, req.context and req.context.include_declaration or false)
end

function Core:document_highlight(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDocumentHighlight") and arg or self:request_from_lsp("textDocument/documentHighlight", arg)
    if req.kind ~= "ReqDocumentHighlight" then error("document_highlight: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspDocumentHighlightList({}) end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return C.LspDocumentHighlightList({}) end
    return self.adapter:document_highlight(doc.file, subject)
end

function Core:to_lsp(v)
    if v == nil then return nil end
    if type(v) ~= "table" then return v end
    local tag = tostring(v):match("^Lua%.([%w_]+)%(") or v.kind
    if tag == "LspPos" then return { line = v.line, character = v.character } end
    if tag == "LspRange" then return { start = self:to_lsp(v.start), ["end"] = self:to_lsp(v.stop) } end
    if tag == "LspLocation" then return { uri = v.uri, range = self:to_lsp(v.range) } end
    if tag == "LspLocationList" then
        local out = {}; for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end; return out
    end
    if tag == "LspDiagnostic" then
        return { range = self:to_lsp(v.range), severity = v.severity,
            source = v.source, code = v.code, message = v.message }
    end
    if tag == "LspDiagnosticList" then
        local out = {}; for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end; return out
    end
    if tag == "LspDiagnosticReport" then
        local items = {}; for i = 1, #v.items do items[i] = self:to_lsp(v.items[i]) end
        return { kind = v.kind, items = items, uri = v.uri, version = v.version }
    end
    if tag == "LspMarkupContent" then return { kind = v.kind, value = v.value } end
    if tag == "LspHover" then return { contents = self:to_lsp(v.contents), range = self:to_lsp(v.range) } end
    if tag == "LspHoverHit" then return self:to_lsp(v.value) end
    if tag == "LspHoverMiss" then return nil end
    if tag == "LspDocumentHighlight" then return { range = self:to_lsp(v.range), kind = v.kind } end
    if tag == "LspDocumentHighlightList" then
        local out = {}; for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end; return out
    end
    return v
end

function Core:completion(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCompletion") and arg or self:request_from_lsp("textDocument/completion", arg)
    if req.kind ~= "ReqCompletion" then error("completion: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._complete_engine then return C.CompletionList({}, false) end

    -- Figure out prefix from position
    local prefix = ""
    if self.position_to_anchor then
        -- Use the text at cursor to determine prefix
        local lines = {}
        for line in (doc.text or ""):gmatch("[^\n]*") do lines[#lines + 1] = line end
        local ln = lines[req.position.line + 1] or ""
        local col = req.position.character
        local before = ln:sub(1, col)
        prefix = before:match("([%w_]+)$") or ""
    end

    return self._complete_engine.complete(C.CompletionQuery(doc.file, req.position, prefix))
end

function Core:document_symbol(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDocumentSymbol") and arg or self:request_from_lsp("textDocument/documentSymbol", arg)
    if req.kind ~= "ReqDocumentSymbol" then error("document_symbol: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._docsymbols_engine then return C.DocSymbolList({}) end
    local items = pvm.drain(self._docsymbols_engine.doc_symbols(doc.file))
    return C.DocSymbolList(items)
end

function Core:signature_help(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSignatureHelp") and arg or self:request_from_lsp("textDocument/signatureHelp", arg)
    if req.kind ~= "ReqSignatureHelp" then error("signature_help: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._sighelp_engine then return C.SignatureHelp({}, 0) end
    return self._sighelp_engine.sig_help(C.SignatureQuery(doc.file, req.position))
end

function Core:rename(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqRename") and arg or self:request_from_lsp("textDocument/rename", arg)
    if req.kind ~= "ReqRename" then error("rename: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._rename_engine then return C.RenameFail("not available") end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return C.RenameFail("no symbol at position") end
    local anchor = type(subject) == "table" and tostring(subject):match("^Lua%.AnchorRef%(") and subject
        or C.AnchorRef(tostring(subject))
    return self._rename_engine.rename(C.RenameQuery(doc.file, anchor, req.new_name))
end

function Core:prepare_rename(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqPrepareRename") and arg or self:request_from_lsp("textDocument/prepareRename", arg)
    if req.kind ~= "ReqPrepareRename" then error("prepare_rename: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._rename_engine then return nil end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return nil end
    local anchor = type(subject) == "table" and tostring(subject):match("^Lua%.AnchorRef%(") and subject
        or C.AnchorRef(tostring(subject))
    return self._rename_engine.prepare_rename(
        C.RenameQuery(doc.file, anchor, ""))
end

function Core:handle_request(req)
    local k = req and req.kind
    if k == "ReqDidOpen" then self:did_open(req); return nil end
    if k == "ReqDidChange" then self:did_change(req); return nil end
    if k == "ReqDidClose" then self:did_close(req); return nil end
    if k == "ReqHover" then return self:hover(req) end
    if k == "ReqDefinition" then return self:definition(req) end
    if k == "ReqReferences" then return self:references(req) end
    if k == "ReqDocumentHighlight" then return self:document_highlight(req) end
    if k == "ReqDiagnostic" then return self:diagnostic(req) end
    if k == "ReqCompletion" then return self:completion(req) end
    if k == "ReqDocumentSymbol" then return self:document_symbol(req) end
    if k == "ReqSignatureHelp" then return self:signature_help(req) end
    if k == "ReqRename" then return self:rename(req) end
    if k == "ReqPrepareRename" then return self:prepare_rename(req) end
    if k == "ReqInvalid" then error(tostring(req.reason or "invalid request"), 2) end
    error("invalid request kind", 2)
end

function Core:handle_lsp(method, params) return self:to_lsp(self:handle(method, params)) end
function Core:handle(method, params) return self:handle_request(self:request_from_lsp(method, params)) end

return { new = function(opts) return Core.new(opts) end }
