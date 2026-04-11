-- bench/lua_lsp_adapter_v1.lua
--
-- ASDL-first LSP IR adapter over lua_lsp_semantics_v1.
-- Returns LuaLsp ASDL nodes only (no Lua table payloads).

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local Semantics = require("bench.lua_lsp_semantics_v1")

local Adapter = {}
Adapter.__index = Adapter

local SEVERITY = {
    ["undefined-global"] = 1,
    ["unknown-type"] = 1,
    ["redeclare-local"] = 2,
    ["shadowing-local"] = 3,
    ["shadowing-global"] = 3,
    ["unused-local"] = 4,
    ["unused-param"] = 4,
}

local function anchor_ref(C, v)
    if not v then return nil end
    if type(v) == "table" then
        local tv = tostring(v)
        if tv:match("^LuaLsp%.AnchorRef%(") then return v end
    end
    return C.AnchorRef(tostring(v))
end

local function query_subject(C, v)
    if not v then return C.QueryMissing() end
    if type(v) == "table" and v.kind == "TNamed" then
        return C.QueryTypeName(v.name)
    end
    if type(v) == "string" then
        return C.QueryTypeName(v)
    end
    return C.QueryAnchor(anchor_ref(C, v))
end

local function contains_anchor(entries, aid)
    for i = 1, #entries do
        if entries[i].anchor.id == aid then return true end
    end
    return false
end

local function mk_range(C, sl, sc, el, ec)
    return C.LspRange(C.LspPos(sl, sc), C.LspPos(el, ec))
end

function Adapter.new(engine, opts)
    local self = setmetatable({}, Adapter)
    self.engine = engine or Semantics.new()
    self.opts = opts or {}

    local C = self.engine.C

    local lsp_range_for = pvm.lower("lsp_range_for", function(q)
        local anchor = q.anchor

        if self.opts.anchor_to_range then
            local meta = self.opts.meta_for_file and self.opts.meta_for_file(q.file) or nil
            local ok, r = pcall(self.opts.anchor_to_range, q.file, anchor, anchor and anchor.id or nil, meta)
            if ok and r and r.start and r["end"] then
                return mk_range(C,
                    r.start.line or 0,
                    r.start.character or 0,
                    r["end"].line or 0,
                    r["end"].character or 1)
            end
        end

        local idx = self.engine:index(q.file)
        local aid = anchor and anchor.id or ""
        local rank = 1

        for i = 1, #idx.defs do
            if idx.defs[i].anchor and idx.defs[i].anchor.id == aid then rank = i; break end
        end
        for i = 1, #idx.uses do
            if idx.uses[i].anchor and idx.uses[i].anchor.id == aid then rank = #idx.defs + i; break end
        end
        for i = 1, #idx.unresolved do
            if idx.unresolved[i].anchor and idx.unresolved[i].anchor.id == aid then rank = #idx.defs + #idx.uses + i; break end
        end

        local line = math.max(0, rank - 1)
        return mk_range(C, line, 0, line, 1)
    end)

    local all_anchor_entries = pvm.lower("lsp_all_anchor_entries", function(file)
        local out = {}

        local function add(anchor, kind, name)
            if not anchor then return end
            if contains_anchor(out, anchor.id) then return end
            local range = lsp_range_for(C.LspRangeQuery(file, anchor))
            out[#out + 1] = C.AnchorEntry(anchor, kind, name, range)
        end

        local idx = self.engine:index(file)
        for i = 1, #idx.defs do
            local d = idx.defs[i]
            add(d.anchor, "def", d.name)
        end
        for i = 1, #idx.uses do
            local u = idx.uses[i]
            add(u.anchor, "use", u.name)
        end
        for i = 1, #idx.unresolved do
            local u = idx.unresolved[i]
            add(u.anchor, "unresolved", u.name)
        end

        local env = self.engine.resolve_named_types(file)
        for i = 1, #env.classes do
            local cls = env.classes[i]
            add(cls.anchor, "type-class", cls.name)
            for j = 1, #cls.fields do
                local f = cls.fields[j]
                add(f.anchor, "type-field", cls.name .. "." .. f.name)
            end
        end
        for i = 1, #env.aliases do
            local a = env.aliases[i]
            add(a.anchor, "type-alias", a.name)
        end
        for i = 1, #env.generics do
            local g = env.generics[i]
            add(g.anchor, "type-generic", g.name)
        end

        table.sort(out, function(a, b)
            local as, bs = a.range.start, b.range.start
            if as.line ~= bs.line then return as.line < bs.line end
            return as.character < bs.character
        end)

        return C.AnchorEntryList(out)
    end)

    local anchor_at_position = pvm.lower("lsp_anchor_at_position", function(q)
        local entries = all_anchor_entries(q.file).items
        local line = q.position.line
        local ch = q.position.character
        local prefer = q.prefer_kind or ""

        local best = nil
        for i = 1, #entries do
            local e = entries[i]
            local rs, re = e.range.start, e.range.stop
            local hit = (line > rs.line or (line == rs.line and ch >= rs.character))
                and (line < re.line or (line == re.line and ch <= re.character))
            if hit then
                if prefer ~= "" and e.kind == prefer then
                    return C.AnchorPickHit(e.anchor, e)
                end
                if not best then best = e end
            end
        end

        if best then return C.AnchorPickHit(best.anchor, best) end
        return C.AnchorPickMiss()
    end)

    local lsp_diagnostics = pvm.lower("lsp_diagnostics", function(file)
        local src = self.engine.diagnostics(file).items
        local out = {}
        for i = 1, #src do
            local d = src[i]
            out[i] = C.LspDiagnostic(
                lsp_range_for(C.LspRangeQuery(file, d.anchor)),
                SEVERITY[d.code] or 2,
                "lua-lsp-pvm",
                d.code,
                d.message
            )
        end
        return C.LspDiagnosticList(out)
    end)

    local lsp_hover = pvm.lower("lsp_hover", function(q)
        local h = self.engine:hover(q.file, (q.subject.kind == "QueryAnchor") and q.subject.anchor or q.subject.name)
        if not h or h.kind == "HoverMissing" then return C.LspHoverMiss() end

        local msg
        if h.kind == "HoverSymbol" then
            msg = string.format("`%s` (%s, scope=%s)\n\nuses: %d, defs: %d",
                tostring(h.name), tostring(h.symbol_kind), tostring(h.scope), h.uses or 0, h.defs or 0)
        elseif h.kind == "HoverType" then
            if (h.fields or 0) > 0 then
                msg = string.format("type `%s` (%s)\n\nfields: %d", tostring(h.name), tostring(h.detail), h.fields)
            else
                msg = string.format("type `%s` (%s)", tostring(h.name), tostring(h.detail))
            end
        else
            msg = tostring(h.name) .. " (" .. tostring(h.detail) .. ")"
        end

        local range = mk_range(C, 0, 0, 0, 1)
        if q.subject.kind == "QueryAnchor" then
            range = lsp_range_for(C.LspRangeQuery(q.file, q.subject.anchor))
        end

        return C.LspHoverHit(C.LspHover(C.LspMarkupContent("markdown", msg), range))
    end)

    local lsp_definition = pvm.lower("lsp_definition", function(q)
        local r = self.engine:goto_definition(q.file, (q.subject.kind == "QueryAnchor") and q.subject.anchor or q.subject.name)
        if not r or r.kind ~= "DefHit" or not r.anchor then return C.LspLocationList({}) end
        return C.LspLocationList({
            C.LspLocation(q.file.uri, lsp_range_for(C.LspRangeQuery(q.file, r.anchor)))
        })
    end)

    local lsp_references = pvm.lower("lsp_references", function(q)
        local rr = self.engine:find_references(q.file,
            (q.subject.kind == "QueryAnchor") and q.subject.anchor or q.subject.name,
            q.include_declaration and true or false)
        local refs = rr.refs or {}
        local out = {}
        for i = 1, #refs do
            out[i] = C.LspLocation(q.file.uri, lsp_range_for(C.LspRangeQuery(q.file, refs[i].anchor)))
        end
        return C.LspLocationList(out)
    end)

    local lsp_document_highlight = pvm.lower("lsp_document_highlight", function(q)
        local rr = self.engine:find_references(q.file,
            (q.subject.kind == "QueryAnchor") and q.subject.anchor or q.subject.name,
            true)
        local refs = rr.refs or {}
        local out = {}
        for i = 1, #refs do
            local r = refs[i]
            local kind = (r.kind == "local" or r.kind == "global" or r.kind == "param") and 3 or 2
            out[i] = C.LspDocumentHighlight(lsp_range_for(C.LspRangeQuery(q.file, r.anchor)), kind)
        end
        return C.LspDocumentHighlightList(out)
    end)

    self._lsp_range_for = lsp_range_for
    self._all_anchor_entries = all_anchor_entries
    self._anchor_at_position = anchor_at_position
    self._lsp_diagnostics = lsp_diagnostics
    self._lsp_hover = lsp_hover
    self._lsp_definition = lsp_definition
    self._lsp_references = lsp_references
    self._lsp_document_highlight = lsp_document_highlight

    return self
end

function Adapter:all_anchor_entries(file)
    return self._all_anchor_entries(file)
end

function Adapter:anchor_at_position(file, position, prefer_kind)
    local C = self.engine.C
    local pos = C.LspPos(position and position.line or 0, position and position.character or 0)
    return self._anchor_at_position(C.LspPositionQuery(file, pos, prefer_kind or ""))
end

function Adapter:diagnostics(file)
    return self._lsp_diagnostics(file)
end

function Adapter:hover(file, anchor_or_type)
    local C = self.engine.C
    return self._lsp_hover(C.SubjectQuery(file, query_subject(C, anchor_or_type)))
end

function Adapter:definition(file, anchor_or_type)
    local C = self.engine.C
    return self._lsp_definition(C.SubjectQuery(file, query_subject(C, anchor_or_type)))
end

function Adapter:references(file, anchor_or_type, include_declaration)
    local C = self.engine.C
    return self._lsp_references(C.RefQuery(file, query_subject(C, anchor_or_type), include_declaration and true or false))
end

function Adapter:document_highlight(file, anchor_or_type)
    local C = self.engine.C
    return self._lsp_document_highlight(C.SubjectQuery(file, query_subject(C, anchor_or_type)))
end

function Adapter:reset()
    self.engine:reset()
    self._lsp_range_for:reset()
    self._all_anchor_entries:reset()
    self._anchor_at_position:reset()
    self._lsp_diagnostics:reset()
    self._lsp_hover:reset()
    self._lsp_definition:reset()
    self._lsp_references:reset()
    self._lsp_document_highlight:reset()
end

return {
    new = function(engine, opts) return Adapter.new(engine, opts) end
}
