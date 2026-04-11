-- bench/lua_lsp_server_core_v1.lua
--
-- Minimal in-memory LSP server core with ASDL-typed request/state/response IR.
--
-- Features:
--   - textDocument/didOpen
--   - textDocument/didChange
--   - textDocument/didClose
--   - textDocument/hover
--   - textDocument/definition
--   - textDocument/references
--   - textDocument/documentHighlight
--   - textDocument/diagnostic (pull)
--
-- Notes:
--   - You provide `parse(uri, text, prev_file, C, params) -> file_ast [, server_meta]`
--   - Optionally provide `position_to_anchor(file, position, doc, adapter, req) -> anchor`
--   - `handle()` returns ASDL IR nodes; `handle_lsp()` serializes at boundary.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Semantics = require("bench.lua_lsp_semantics_v1")
local AdapterMod = require("bench.lua_lsp_adapter_v1")

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
        -- Full-sync style: use latest text blob.
        local last = changes[#changes]
        if last and last.text ~= nil then return last.text end
    end

    return nil
end

local function anchor_ref(C, v)
    if not v then return nil end
    if type(v) == "table" and tostring(v):match("^LuaLsp%.AnchorRef%(") then return v end
    return C.AnchorRef(tostring(v))
end

local function lsp_range_from(C, raw_range, pos)
    if type(raw_range) == "table" and tostring(raw_range):match("^LuaLsp%.LspRange%(") then
        return raw_range
    end
    if type(raw_range) == "table" and raw_range.start and raw_range.stop then
        return C.LspRange(
            C.LspPos(raw_range.start.line or 0, raw_range.start.character or 0),
            C.LspPos(raw_range.stop.line or 0, raw_range.stop.character or 1)
        )
    end
    if type(raw_range) == "table" and raw_range.start and raw_range["end"] then
        return C.LspRange(
            C.LspPos(raw_range.start.line or 0, raw_range.start.character or 0),
            C.LspPos(raw_range["end"].line or 0, raw_range["end"].character or 1)
        )
    end
    if pos then
        return C.LspRange(
            C.LspPos(pos.line or 0, pos.start or 0),
            C.LspPos(pos.line or 0, pos["end"] or ((pos.start or 0) + 1))
        )
    end
    return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
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
            aopts.meta_for_file = function(file)
                return self:_meta_for_file(file)
            end
        end
        self.adapter = AdapterMod.new(self.engine, aopts)
    end

    self._doc_lookup = pvm.lower("core_doc_lookup", function(q)
        local docs = q.store.docs
        for i = 1, #docs do
            if docs[i].uri == q.uri then
                return C.ServerDocHit(docs[i])
            end
        end
        return C.ServerDocMiss()
    end)

    return self
end

function Core:_meta_to_asdl(file, meta)
    local C = self.engine.C
    if type(meta) == "table" and tostring(meta):match("^LuaLsp%.ServerMeta%(") then
        return meta
    end

    local positions = {}
    local parse_error = ""

    if type(meta) == "table" then
        local ps = meta.positions or {}
        for i = 1, #ps do
            local p = ps[i]
            positions[#positions + 1] = C.ServerAnchorPoint(
                anchor_ref(C, p.anchor or file),
                lsp_range_from(C, p.range, p),
                tostring(p.label or "")
            )
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
    local out = {}
    local replaced = false
    for i = 1, #old do
        local d = old[i]
        if d.uri == uri then
            out[#out + 1] = next_doc
            replaced = true
        else
            out[#out + 1] = d
        end
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
    for i = 1, #docs do
        local d = docs[i]
        if d.file == file then return d.meta end
    end
    return nil
end

function Core:_parse(uri, text, prev_file, version, params)
    if not self.parse then
        error("lua_lsp_server_core_v1: parse callback required when no AST provided", 2)
    end

    local parse_params = params
    if not (type(parse_params) == "table" and not tostring(parse_params):match("^LuaLsp%.")) then
        parse_params = {
            uri = uri,
            version = version,
            text = text,
            textDocument = { uri = uri, version = version, text = text },
        }
    end

    local file, meta = self.parse(uri, text, prev_file, self.engine.C, parse_params)
    if not file then
        error("lua_lsp_server_core_v1: parse callback returned nil file", 2)
    end
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
            for i = 1, #raw do
                changes[#changes + 1] = C.LspTextChange(tostring(raw[i] and raw[i].text or ""))
            end
        end
        if #changes == 0 then
            local t = text_from_params(params)
            if t ~= nil then changes[1] = C.LspTextChange(t) end
        end
        return C.ReqDidChange(C.LspVersionedDoc(uri, version_from_params(params) or 0), changes)
    end

    if method == "textDocument/didClose" then
        return C.ReqDidClose(C.LspDocIdentifier(uri))
    end

    if method == "textDocument/hover" then
        return C.ReqHover(C.LspDocIdentifier(uri), pos, subject)
    end
    if method == "textDocument/definition" then
        return C.ReqDefinition(C.LspDocIdentifier(uri), pos, subject)
    end
    if method == "textDocument/references" then
        local include = (params.context and params.context.includeDeclaration) and true or (params.includeDeclaration and true or false)
        return C.ReqReferences(C.LspDocIdentifier(uri), pos, subject, C.LspReferenceContext(include))
    end
    if method == "textDocument/documentHighlight" then
        return C.ReqDocumentHighlight(C.LspDocIdentifier(uri), pos, subject)
    end
    if method == "textDocument/diagnostic" then
        return C.ReqDiagnostic(C.LspDocIdentifier(uri))
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
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
    local req = (tag == "ReqDidOpen") and arg or self:request_from_lsp("textDocument/didOpen", arg)
    if req.kind ~= "ReqDidOpen" then error("did_open: invalid request", 2) end

    local raw = (type(arg) == "table" and not tostring(arg):match("^LuaLsp%.")) and arg or nil
    local file = raw and raw.file or nil
    local meta = raw and raw.meta or nil

    if not file then
        file, meta = self:_parse(req.doc.uri, req.doc.text or "", nil, req.doc.version or 0, raw or req)
    end

    return self:_set_doc(req.doc.uri, req.doc.version or 0, req.doc.text or "", file, meta)
end

function Core:did_change(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
    local req = (tag == "ReqDidChange") and arg or self:request_from_lsp("textDocument/didChange", arg)
    if req.kind ~= "ReqDidChange" then error("did_change: invalid request", 2) end

    local uri = req.doc.uri
    local doc = self:_doc(uri)
    if not doc then error("did_change: unknown uri " .. tostring(uri), 2) end

    local raw = (type(arg) == "table" and not tostring(arg):match("^LuaLsp%.")) and arg or nil
    local file = raw and raw.file or nil
    local meta = raw and raw.meta or nil

    local next_text = doc.text or ""
    if #req.changes > 0 then
        next_text = req.changes[#req.changes].text
    end

    if not file then
        file, meta = self:_parse(uri, next_text, doc.file, req.doc.version or doc.version or 0, raw or req)
    end

    return self:_set_doc(uri, req.doc.version or doc.version, next_text, file, meta)
end

function Core:did_close(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
    local req = (tag == "ReqDidClose") and arg or self:request_from_lsp("textDocument/didClose", arg)
    if req.kind ~= "ReqDidClose" then error("did_close: invalid request", 2) end

    local old = self.docs.docs
    local out = {}
    for i = 1, #old do
        if old[i].uri ~= req.doc.uri then out[#out + 1] = old[i] end
    end
    self.docs = C.ServerDocStore(out)
    return true
end

function Core:diagnostic(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
    local req = (tag == "ReqDiagnostic") and arg or self:request_from_lsp("textDocument/diagnostic", arg)
    if req.kind ~= "ReqDiagnostic" then error("diagnostic: invalid request", 2) end

    local uri = req.doc.uri
    local doc = self:_doc(uri)
    if not doc then return C.LspDiagnosticReport("full", {}, uri or "", 0) end

    local items = {}
    local ds = self.adapter:diagnostics(doc.file).items
    for i = 1, #ds do items[i] = ds[i] end

    if doc.meta and doc.meta.parse_error and doc.meta.parse_error ~= "" then
        items[#items + 1] = C.LspDiagnostic(
            C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)),
            1,
            "lua-lsp-pvm",
            "parse-error",
            tostring(doc.meta.parse_error)
        )
    end

    return C.LspDiagnosticReport("full", items, uri, doc.version or 0)
end

function Core:hover(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
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
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
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
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
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
    local tag = tostring(arg):match("^LuaLsp%.([%w_]+)%(")
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

    local tag = tostring(v):match("^LuaLsp%.([%w_]+)%(") or v.kind

    if tag == "LspPos" then
        return { line = v.line, character = v.character }
    end
    if tag == "LspRange" then
        return {
            start = self:to_lsp(v.start),
            ["end"] = self:to_lsp(v.stop),
        }
    end
    if tag == "LspLocation" then
        return { uri = v.uri, range = self:to_lsp(v.range) }
    end
    if tag == "LspLocationList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end
    if tag == "LspDiagnostic" then
        return {
            range = self:to_lsp(v.range),
            severity = v.severity,
            source = v.source,
            code = v.code,
            message = v.message,
        }
    end
    if tag == "LspDiagnosticList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end
    if tag == "LspDiagnosticReport" then
        local items = {}
        for i = 1, #v.items do items[i] = self:to_lsp(v.items[i]) end
        return { kind = v.kind, items = items, uri = v.uri, version = v.version }
    end
    if tag == "LspMarkupContent" then
        return { kind = v.kind, value = v.value }
    end
    if tag == "LspHover" then
        return { contents = self:to_lsp(v.contents), range = self:to_lsp(v.range) }
    end
    if tag == "LspHoverHit" then
        return self:to_lsp(v.value)
    end
    if tag == "LspHoverMiss" then
        return nil
    end
    if tag == "LspDocumentHighlight" then
        return { range = self:to_lsp(v.range), kind = v.kind }
    end
    if tag == "LspDocumentHighlightList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    return v
end

function Core:handle_request(req)
    local k = req and req.kind

    if k == "ReqDidOpen" then
        self:did_open(req)
        return nil
    end
    if k == "ReqDidChange" then
        self:did_change(req)
        return nil
    end
    if k == "ReqDidClose" then
        self:did_close(req)
        return nil
    end

    if k == "ReqHover" then return self:hover(req) end
    if k == "ReqDefinition" then return self:definition(req) end
    if k == "ReqReferences" then return self:references(req) end
    if k == "ReqDocumentHighlight" then return self:document_highlight(req) end
    if k == "ReqDiagnostic" then return self:diagnostic(req) end

    if k == "ReqInvalid" then
        error(tostring(req.reason or "invalid request"), 2)
    end

    error("invalid request kind", 2)
end

function Core:handle_lsp(method, params)
    return self:to_lsp(self:handle(method, params))
end

function Core:handle(method, params)
    local req = self:request_from_lsp(method, params)
    return self:handle_request(req)
end

return {
    new = function(opts) return Core.new(opts) end,
}
