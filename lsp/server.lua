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
    if pvm.classof(v) == C.AnchorRef then return v end
    return C.AnchorRef(tostring(v))
end

local function is_asdl(v)
    return pvm.classof(v) ~= false
end

local function is_plain_table(v)
    return type(v) == "table" and not is_asdl(v)
end

local function doc_uri(doc)
    return doc and doc.uri or ""
end

local function doc_text(doc)
    return doc and doc.text or ""
end

local function doc_version(doc)
    return doc and doc.version or 0
end

local function line_bounds(text, line0)
    local line = line0 or 0
    if line < 0 then line = 0 end

    local pos = 1
    local cur = 0
    while cur < line do
        local nl = text:find("\n", pos, true)
        if not nl then return #text + 1, #text + 1 end
        pos = nl + 1
        cur = cur + 1
    end

    local line_end = text:find("\n", pos, true)
    if not line_end then line_end = #text + 1 end
    return pos, line_end
end

local function utf8_char_len_at(s, i)
    local b = s:byte(i)
    if not b then return 0 end
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

local function utf16_col_to_byte_in_line(line_text, col0)
    local target = col0 or 0
    if target < 0 then target = 0 end

    local count = 0
    local i = 1
    local n = #line_text

    while i <= n do
        if target <= count then return i end
        local len = utf8_char_len_at(line_text, i)
        if len == 0 then break end
        if i + len - 1 > n then len = 1 end

        local units = (len == 4) and 2 or 1
        if target < count + units then
            return i
        end
        count = count + units
        i = i + len
        if target == count then
            return i
        end
    end

    return n + 1
end

local function line_utf16_to_offset(text, line0, char0)
    local line_start, line_end = line_bounds(text, line0)
    if line_start > #text + 1 then return #text + 1 end
    local line_text = text:sub(line_start, line_end - 1)
    local byte_in_line = utf16_col_to_byte_in_line(line_text, char0)
    return line_start + byte_in_line - 1
end

local function apply_lsp_change(text, change)
    if not change.has_range then
        return change.text or ""
    end

    local r = change.range
    local s = r and r.start
    local e = r and r.stop
    if not s or not e then
        return change.text or ""
    end

    local from = line_utf16_to_offset(text, s.line, s.character)
    local to = line_utf16_to_offset(text, e.line, e.character)
    if to < from then to = from end

    return text:sub(1, from - 1) .. (change.text or "") .. text:sub(to)
end

local function word_at_position(text, line0, char0)
    local line_start, line_end = line_bounds(text, line0)
    if line_start > #text + 1 then return nil end
    local line_text = text:sub(line_start, line_end - 1)
    if #line_text == 0 then return nil end

    local i = utf16_col_to_byte_in_line(line_text, char0)
    if i < 1 then i = 1 end
    if i > #line_text then i = #line_text end

    local function is_ident_char(c)
        return c and c:match("[%w_]") ~= nil
    end

    if not is_ident_char(line_text:sub(i, i)) and i > 1 and is_ident_char(line_text:sub(i - 1, i - 1)) then
        i = i - 1
    end
    if not is_ident_char(line_text:sub(i, i)) then
        return nil
    end

    local l = i
    while l > 1 and is_ident_char(line_text:sub(l - 1, l - 1)) do l = l - 1 end
    local r = i
    while r < #line_text and is_ident_char(line_text:sub(r + 1, r + 1)) do r = r + 1 end
    return line_text:sub(l, r)
end

local function normalize_module_name(name)
    if not name then return nil end
    local n = tostring(name):gsub("\\", "/"):gsub("%.lua$", "")
    n = n:gsub("/", ".")
    n = n:gsub("^%./", "")
    n = n:gsub("^%.", "")
    n = n:gsub("%.$", "")
    return n
end

local function uri_to_path(uri)
    if type(uri) ~= "string" then return nil end
    local p = uri:match("^file://(.*)$") or uri
    p = p:gsub("^localhost", "")
    p = p:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return p
end

local function module_names_for_uri(uri)
    local path = uri_to_path(uri)
    if not path then return {} end

    local names, seen = {}, {}
    local function add(n)
        n = normalize_module_name(n)
        if not n or n == "" or seen[n] then return end
        seen[n] = true
        names[#names + 1] = n
    end

    local noext = path:gsub("%.lua$", "")
    local base = noext:match("([^/]+)$")
    add(base)

    local cwd = os.getenv("PWD") or ""
    if cwd ~= "" and noext:sub(1, #cwd) == cwd then
        local rel = noext:sub(#cwd + 2)
        add(rel)
    end

    if noext:match("/init$") then
        local parent = noext:gsub("/init$", "")
        add(parent:match("([^/]+)$"))
        if cwd ~= "" and parent:sub(1, #cwd) == cwd then
            local relp = parent:sub(#cwd + 2)
            add(relp)
        end
    end

    return names
end

local function module_name_at_position(text, line0, char0)
    local line_start, line_end = line_bounds(text, line0)
    if line_start > #text + 1 then return nil end
    local line_text = text:sub(line_start, line_end - 1)
    if #line_text == 0 then return nil end

    local byte_col = utf16_col_to_byte_in_line(line_text, char0)
    local i = 1
    while true do
        local s, e = line_text:find("require%s*%(%s*['\"][^'\"]+['\"]%s*%)", i)
        if not s then break end
        local chunk = line_text:sub(s, e)
        local q1, q2, mod = chunk:find("['\"]([^'\"]+)['\"]")
        if q1 and q2 and mod then
            local ns = s + q1
            local ne = s + q2 - 2
            if byte_col >= ns and byte_col <= ne + 1 then
                return normalize_module_name(mod)
            end
        end
        i = e + 1
    end
    return nil
end

local function field_access_at_position(text, line0, char0)
    local line_start, line_end = line_bounds(text, line0)
    if line_start > #text + 1 then return nil, nil end
    local line_text = text:sub(line_start, line_end - 1)
    if #line_text == 0 then return nil, nil end

    local byte_col = utf16_col_to_byte_in_line(line_text, char0)
    local i = 1
    while true do
        local s, e, base, field = line_text:find("([%a_][%w_]*)%s*[%.:]%s*([%a_][%w_]*)", i)
        if not s then break end
        local chunk = line_text:sub(s, e)
        local rel = chunk:find(field, 1, true)
        if rel then
            local fs = s + rel - 1
            local fe = fs + #field - 1
            if byte_col >= fs and byte_col <= fe + 1 then
                local bs = s
                local be = s + #base - 1
                return base, field, bs, be, fs, fe
            end
        end
        i = e + 1
    end
    return nil, nil
end

local function require_alias_map(text)
    local out = {}
    for alias, mod in (text or ""):gmatch("local%s+([%a_][%w_]*)%s*=%s*require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
        out[alias] = normalize_module_name(mod)
    end
    return out
end

local function utf16_len(s)
    local n, i = 0, 1
    while i <= #s do
        local len = utf8_char_len_at(s, i)
        if len <= 0 then len = 1 end
        if i + len - 1 > #s then len = 1 end
        n = n + ((len == 4) and 2 or 1)
        i = i + len
    end
    return n
end

local function lsp_range_from_params(C, r)
    if type(r) ~= "table" or type(r.start) ~= "table" or type(r["end"]) ~= "table" then
        return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0))
    end
    return C.LspRange(
        C.LspPos(r.start.line or 0, r.start.character or 0),
        C.LspPos(r["end"].line or 0, r["end"].character or 0)
    )
end

local function byte_to_utf16_col_in_line(line_text, byte_index)
    local target = byte_index or 1
    if target < 1 then target = 1 end
    if target > #line_text + 1 then target = #line_text + 1 end
    local col, i = 0, 1
    while i < target do
        local len = utf8_char_len_at(line_text, i)
        if len <= 0 then len = 1 end
        if i + len - 1 > #line_text then len = 1 end
        col = col + ((len == 4) and 2 or 1)
        i = i + len
    end
    return col
end

local function completion_item_from_lua(C, it)
    it = it or {}
    local doc = it.documentation
    if type(doc) == "table" then doc = doc.value end
    return C.LspCompletionItem(
        tostring(it.label or ""),
        tonumber(it.kind) or 1,
        tostring(it.detail or ""),
        tostring(it.sortText or it.sort_text or ""),
        tostring(it.insertText or it.insert_text or it.label or ""),
        tostring(doc or "")
    )
end

local function code_action_kind_from_lua(C, k)
    local s = tostring(k or "quickfix")
    if s:find("^refactor") then return C.CodeActionRefactor end
    if s:find("^source") then return C.CodeActionSource end
    return C.CodeActionQuickFix
end

local function code_action_from_lua(C, a)
    a = a or {}
    local edit = C.LspWorkspaceEdit({}, "")
    local e = a.edit

    local function to_text_edits(arr)
        local edits = {}
        if type(arr) == "table" then
            for i = 1, #arr do
                local te = arr[i] or {}
                edits[#edits + 1] = C.LspTextEdit(
                    lsp_range_from_params(C, te.range),
                    tostring(te.newText or te.new_text or "")
                )
            end
        end
        return edits
    end

    if type(e) == "table" then
        if type(e.changes) == "table" then
            -- Current ASDL stores one URI + edit list; choose deterministically.
            local uris, n = {}, 0
            for uri in pairs(e.changes) do
                n = n + 1
                uris[n] = tostring(uri or "")
            end
            table.sort(uris)
            local uri = uris[1]
            if uri then
                edit = C.LspWorkspaceEdit(to_text_edits(e.changes[uri]), uri)
            end
        elseif type(e.documentChanges) == "table" then
            -- Fallback for clients that send documentChanges on resolve.
            local picks = {}
            for i = 1, #e.documentChanges do
                local dc = e.documentChanges[i]
                if type(dc) == "table" then
                    local td = dc.textDocument
                    local uri = (type(td) == "table" and td.uri) or dc.uri
                    if uri and type(dc.edits) == "table" then
                        picks[#picks + 1] = { uri = tostring(uri), edits = dc.edits }
                    end
                end
            end
            table.sort(picks, function(x, y) return x.uri < y.uri end)
            if picks[1] then
                edit = C.LspWorkspaceEdit(to_text_edits(picks[1].edits), picks[1].uri)
            end
        end
    end

    return C.LspCodeAction(tostring(a.title or ""), code_action_kind_from_lua(C, a.kind), edit)
end

local function whole_text_range(C, text)
    local line, col = 0, 0
    local i = 1
    while i <= #text do
        local b = text:byte(i)
        if b == 10 then
            line = line + 1
            col = 0
            i = i + 1
        else
            local len = utf8_char_len_at(text, i)
            if len <= 0 then len = 1 end
            if i + len - 1 > #text then len = 1 end
            col = col + ((len == 4) and 2 or 1)
            i = i + len
        end
    end
    return C.LspRange(C.LspPos(0, 0), C.LspPos(line, col))
end

local function simple_format_text(text, tab_size, insert_spaces)
    local size = tonumber(tab_size) or 4
    if size < 1 then size = 4 end
    local unit = insert_spaces and string.rep(" ", size) or "\t"

    local function normalize_indent(line)
        local ws, rest = line:match("^(%s*)(.*)$")
        ws = ws or ""
        rest = rest or line

        local columns = 0
        for i = 1, #ws do
            local ch = ws:sub(i, i)
            if ch == "\t" then
                columns = columns + size
            elseif ch == " " then
                columns = columns + 1
            end
        end
        local level = math.floor(columns / size)
        return level, rest
    end

    local function opens_block(s)
        if s:match("^if\b.*\bthen%s*$") then return true end
        if s:match("^elseif\b.*\bthen%s*$") then return true end
        if s:match("^else%s*$") then return true end
        if s:match("^while\b.*\bdo%s*$") then return true end
        if s:match("^for\b.*\bdo%s*$") then return true end
        if s:match("^do%s*$") then return true end
        if s:match("^repeat%s*$") then return true end
        if s:match("^function\b") then return true end
        if s:match("^local%s+function\b") then return true end
        return false
    end

    local function closes_before(s)
        if s:match("^end\b") then return true end
        if s:match("^until\b") then return true end
        if s:match("^elseif\b") then return true end
        if s:match("^else\b") then return true end
        return false
    end

    local raw_lines = {}
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        raw_lines[n] = line
    end
    if n > 0 then n = n - 1 end -- drop synthetic split line

    local out = {}
    local indent = 0
    for i = 1, n do
        local _, rest = normalize_indent(raw_lines[i])
        rest = rest:gsub("[ \t]+$", "")

        if rest ~= "" and closes_before(rest) then
            indent = indent - 1
            if indent < 0 then indent = 0 end
        end

        if rest == "" then
            out[i] = ""
        else
            out[i] = string.rep(unit, indent) .. rest
        end

        if rest ~= "" and opens_block(rest) then
            indent = indent + 1
        end
    end

    local formatted = table.concat(out, "\n")
    if formatted ~= "" and formatted:sub(-1) ~= "\n" then
        formatted = formatted .. "\n"
    end
    return formatted
end

local function signature_context_at_position(text, line0, char0)
    local off = line_utf16_to_offset(text, line0, char0)
    if off < 1 then off = 1 end

    local open = nil
    local depth = 0
    for i = off - 1, 1, -1 do
        local ch = text:sub(i, i)
        if ch == ")" then
            depth = depth + 1
        elseif ch == "(" then
            if depth == 0 then
                open = i
                break
            end
            depth = depth - 1
        end
    end
    if not open then return nil, 0 end

    local j = open - 1
    while j >= 1 and text:sub(j, j):match("%s") do j = j - 1 end
    local e = j
    while j >= 1 and text:sub(j, j):match("[%w_%.:]") do j = j - 1 end
    local callee = text:sub(j + 1, e)
    if callee == "" then return nil, 0 end

    local arg_index = 0
    local sub_depth = 0
    for i = open + 1, off - 1 do
        local ch = text:sub(i, i)
        if ch == "(" then
            sub_depth = sub_depth + 1
        elseif ch == ")" then
            if sub_depth > 0 then sub_depth = sub_depth - 1 end
        elseif ch == "," and sub_depth == 0 then
            arg_index = arg_index + 1
        end
    end

    return callee, arg_index
end

function Core.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Core)
    self.engine = opts.engine or Semantics.new(opts.context)
    self.parse = opts.parse
    self.position_to_anchor = opts.position_to_anchor

    local C = self.engine.C
    self.docs = C.ParsedDocStore({})

    if opts.adapter then
        self.adapter = opts.adapter
    else
        self.adapter = AdapterMod.new(self.engine, opts.adapter_opts or {})
    end

    self._doc_lookup = pvm.phase("core_doc_lookup", function(q)
        local docs = q.store.docs
        for i = 1, #docs do
            if doc_uri(docs[i]) == q.uri then return C.ParsedDocHit(docs[i]) end
        end
        return C.ParsedDocMiss
    end)

    return self
end

function Core:_set_doc(doc)
    local C = self.engine.C
    local uri = doc_uri(doc)
    local old = self.docs.docs
    local out, replaced = {}, false
    for i = 1, #old do
        if doc_uri(old[i]) == uri then out[#out + 1] = doc; replaced = true
        else out[#out + 1] = old[i] end
    end
    if not replaced then out[#out + 1] = doc end
    self.docs = C.ParsedDocStore(out)
    return doc
end

function Core:_doc(uri)
    local C = self.engine.C
    local hit = pvm.one(self._doc_lookup(C.ParsedDocQuery(self.docs, uri)))
    if hit.kind == "ParsedDocHit" then return hit.doc end
    return nil
end

function Core:_range_for(doc, anchor)
    local C = self.engine.C
    if self.adapter and self.adapter._lsp_range_for and doc and anchor then
        return pvm.one(self.adapter._lsp_range_for(C.LspRangeQuery(doc, anchor)))
    end
    return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
end

function Core:_workspace_global_locations(name, include_declaration)
    if self._workspace_engine then
        return self._workspace_engine:global_locations(self.docs, name, include_declaration)
    end
    local C = self.engine.C
    return C.LspLocationList({})
end

function Core:_workspace_type_target(name)
    if self._workspace_engine then
        return self._workspace_engine:workspace_type_target(self.docs, name)
    end
    return nil
end

function Core:_expand_type_names(seed)
    if self._workspace_engine then
        return self._workspace_engine:expand_type_names(self.docs, seed)
    end
    return seed or {}
end

function Core:_workspace_type_locations(name)
    if self._workspace_engine then
        return self._workspace_engine:type_locations(self.docs, name)
    end
    local C = self.engine.C
    return C.LspLocationList({})
end

function Core:_workspace_class_field_type_names(class_name, field_name)
    if self._workspace_engine then
        return self._workspace_engine:class_field_type_names(self.docs, class_name, field_name)
    end
    return {}
end

function Core:_workspace_type_implementations(name)
    if self._workspace_engine then
        return self._workspace_engine:type_implementations(self.docs, name)
    end
    local C = self.engine.C
    return C.LspLocationList({})
end

function Core:_module_docs_for_name(name)
    local norm = normalize_module_name(name)
    if not norm or norm == "" then return {} end

    local out = {}
    local docs = self.docs.docs
    for i = 1, #docs do
        local d = docs[i]
        local names = module_names_for_uri(d.uri)
        for j = 1, #names do
            if names[j] == norm then
                out[#out + 1] = d
                break
            end
        end
    end
    return out
end

function Core:_module_doc_locations(name)
    if self._workspace_engine then
        return self._workspace_engine:module_locations(self.docs, name)
    end
    local C = self.engine.C
    return C.LspLocationList({})
end

function Core:_workspace_module_field_locations(module_name, field, include_declaration)
    if self._workspace_engine then
        return self._workspace_engine:module_field_locations(self.docs, module_name, field, include_declaration)
    end
    local C = self.engine.C
    return C.LspLocationList({})
end

function Core:_parse(uri, version, text, prev_doc, params)
    if not self.parse then
        error("lsp/server: parse callback required", 2)
    end
    local parse_params = params
    if not is_plain_table(parse_params) then
        parse_params = {
            uri = uri, version = version, text = text,
            textDocument = { uri = uri, version = version, text = text },
        }
    end
    parse_params.prev_doc = prev_doc
    local doc = self.parse(uri, version, text, prev_doc, self.engine.C, parse_params)
    if not doc then error("lsp/server: parse callback returned nil doc", 2) end
    return doc
end

function Core:request_from_lsp(method, params)
    local C = self.engine.C
    params = params or {}
    local uri = uri_from_params(params) or ""
    local pos0 = params.position or (params.textDocumentPositionParams and params.textDocumentPositionParams.position) or {}
    local pos = C.LspPos(pos0.line or 0, pos0.character or 0)

    local subject = C.QueryMissing
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
        local dummy = C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0))
        if type(raw) == "table" then
            for i = 1, #raw do
                local chg = raw[i] or {}
                local range = dummy
                local has_range = false
                if type(chg.range) == "table" and type(chg.range.start) == "table" and type(chg.range["end"]) == "table" then
                    range = C.LspRange(
                        C.LspPos(chg.range.start.line or 0, chg.range.start.character or 0),
                        C.LspPos(chg.range["end"].line or 0, chg.range["end"].character or 0)
                    )
                    has_range = true
                end
                changes[#changes + 1] = C.LspTextChange(tostring(chg.text or ""), range, has_range)
            end
        end
        if #changes == 0 then
            local t = text_from_params(params)
            if t ~= nil then changes[1] = C.LspTextChange(t, dummy, false) end
        end
        return C.ReqDidChange(C.LspVersionedDoc(uri, version_from_params(params) or 0), changes)
    end
    if method == "textDocument/didClose" then return C.ReqDidClose(C.LspDocIdentifier(uri)) end
    if method == "textDocument/didSave" then return C.ReqDidSave(C.LspDocIdentifier(uri)) end
    if method == "textDocument/hover" then return C.ReqHover(C.LspDocIdentifier(uri), pos, subject) end
    if method == "textDocument/definition" then return C.ReqDefinition(C.LspDocIdentifier(uri), pos, subject) end
    if method == "textDocument/declaration" then return C.ReqDeclaration(C.LspDocIdentifier(uri), pos, subject) end
    if method == "textDocument/implementation" then return C.ReqImplementation(C.LspDocIdentifier(uri), pos, subject) end
    if method == "textDocument/typeDefinition" then return C.ReqTypeDefinition(C.LspDocIdentifier(uri), pos, subject) end
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
    if method == "completionItem/resolve" then
        return C.ReqCompletionResolve(completion_item_from_lua(C, params))
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
    if method == "textDocument/codeAction" then
        return C.ReqCodeAction(C.LspDocIdentifier(uri), lsp_range_from_params(C, params.range))
    end
    if method == "codeAction/resolve" then
        return C.ReqCodeActionResolve(code_action_from_lua(C, params))
    end
    if method == "textDocument/semanticTokens/full" then
        return C.ReqSemanticTokensFull(C.LspDocIdentifier(uri))
    end
    if method == "textDocument/semanticTokens/range" then
        return C.ReqSemanticTokensRange(C.LspDocIdentifier(uri), lsp_range_from_params(C, params.range))
    end
    if method == "textDocument/inlayHint" then
        return C.ReqInlayHint(C.LspDocIdentifier(uri), lsp_range_from_params(C, params.range))
    end
    if method == "textDocument/formatting" or method == "textDocument/rangeFormatting" or method == "textDocument/onTypeFormatting" then
        local opts = params.options or {}
        local fmt_opts = C.LspFormattingOptions(
            tonumber(opts.tabSize) or 4,
            (opts.insertSpaces ~= false),
            true,
            true
        )
        local has_range = (method == "textDocument/rangeFormatting")
        local range = has_range and lsp_range_from_params(C, params.range)
            or C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0))
        return C.ReqFormatting(
            C.LspDocIdentifier(uri),
            fmt_opts,
            range,
            has_range
        )
    end
    if method == "textDocument/foldingRange" then
        return C.ReqFoldingRange(C.LspDocIdentifier(uri))
    end
    if method == "textDocument/selectionRange" then
        local points = {}
        local pp = params.positions
        if type(pp) == "table" then
            for i = 1, #pp do
                local p = pp[i] or {}
                points[#points + 1] = C.LspPos(p.line or 0, p.character or 0)
            end
        end
        if #points == 0 then points[1] = pos end
        return C.ReqSelectionRange(C.LspDocIdentifier(uri), points)
    end
    if method == "textDocument/codeLens" then
        return C.ReqCodeLens(C.LspDocIdentifier(uri))
    end
    if method == "textDocument/documentColor" then
        return C.ReqDocumentColor(C.LspDocIdentifier(uri))
    end
    if method == "workspace/symbol" then
        return C.ReqWorkspaceSymbol(tostring(params.query or ""))
    end
    if method == "workspace/diagnostic" then
        return C.ReqWorkspaceDiagnostic
    end
    if method == "workspace/executeCommand" then
        local args = {}
        local aa = params.arguments
        if type(aa) == "table" then
            for i = 1, #aa do args[i] = tostring(aa[i]) end
        end
        return C.ReqExecuteCommand(tostring(params.command or ""), args)
    end
    return C.ReqInvalid("unsupported method: " .. tostring(method))
end

function Core:_resolve_subject(doc, req, prefer_kind)
    local C = self.engine.C
    if not doc then return nil end
    local subject = req.subject or C.QueryMissing
    if subject.kind == "QueryTypeName" then return subject.name end
    if subject.kind == "QueryAnchor" then return subject.anchor end
    local pos = req.position
    if not pos then return nil end
    local position = { line = pos.line, character = pos.character }
    if self.position_to_anchor then
        local ok, anchor = pcall(self.position_to_anchor, doc, position, self.adapter, req)
        if ok and anchor then return anchor_ref(C, anchor) end
    end
    local pick = pvm.one(self.adapter:anchor_at_position(doc, position, prefer_kind))
    if pick and pick.kind == "AnchorPickHit" then return pick.anchor end
    return nil
end

function Core:did_open(arg)
    local C = self.engine.C
    local req = (pvm.classof(arg) == C.ReqDidOpen) and arg or self:request_from_lsp("textDocument/didOpen", arg)
    if req.kind ~= "ReqDidOpen" then error("did_open: invalid request", 2) end
    local raw = is_plain_table(arg) and arg or nil
    local doc = raw and raw.doc or nil
    if not doc then
        doc = self:_parse(req.doc.uri, req.doc.version or 0, req.doc.text or "", nil, raw or req)
    end
    return self:_set_doc(doc)
end

function Core:did_change(arg)
    local C = self.engine.C
    local req = (pvm.classof(arg) == C.ReqDidChange) and arg or self:request_from_lsp("textDocument/didChange", arg)
    if req.kind ~= "ReqDidChange" then error("did_change: invalid request", 2) end
    local uri = req.doc.uri
    local doc = self:_doc(uri)
    if not doc then error("did_change: unknown uri " .. tostring(uri), 2) end
    local raw = is_plain_table(arg) and arg or nil
    local next_doc = raw and raw.doc or nil
    local next_text = doc_text(doc)
    if #req.changes > 0 then
        for i = 1, #req.changes do
            next_text = apply_lsp_change(next_text, req.changes[i])
        end
    end
    if not next_doc then
        next_doc = self:_parse(uri, req.doc.version or doc_version(doc), next_text, doc, raw or req)
    end
    return self:_set_doc(next_doc)
end

function Core:did_close(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDidClose") and arg or self:request_from_lsp("textDocument/didClose", arg)
    if req.kind ~= "ReqDidClose" then error("did_close: invalid request", 2) end
    local old = self.docs.docs
    local out = {}
    for i = 1, #old do if doc_uri(old[i]) ~= req.doc.uri then out[#out + 1] = old[i] end end
    self.docs = C.ParsedDocStore(out)
    return true
end

function Core:did_save(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDidSave") and arg or self:request_from_lsp("textDocument/didSave", arg)
    if req.kind ~= "ReqDidSave" then error("did_save: invalid request", 2) end
    return true
end

function Core:diagnostic(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDiagnostic") and arg or self:request_from_lsp("textDocument/diagnostic", arg)
    if req.kind ~= "ReqDiagnostic" then error("diagnostic: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspDiagnosticReport(C.DiagReportFull, {}, req.doc.uri or "", 0) end
    local items = {}
    local ds = pvm.one(self.adapter:diagnostics(doc)).items
    for i = 1, #ds do items[i] = ds[i] end
    if doc.status and doc.status.kind == "ParseError" then
        items[#items + 1] = C.LspDiagnostic(
            C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)), 1,
            "lua-lsp-pvm", "parse-error", tostring(doc.status.message or "parse error"))
    end
    return C.LspDiagnosticReport(C.DiagReportFull, items, doc_uri(doc), doc_version(doc))
end

function Core:hover(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqHover") and arg or self:request_from_lsp("textDocument/hover", arg)
    if req.kind ~= "ReqHover" then error("hover: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspHoverMiss end
    local subject = self:_resolve_subject(doc, req)
    if not subject then return C.LspHoverMiss end
    return pvm.one(self.adapter:hover(doc, subject))
end

function Core:definition(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDefinition") and arg or self:request_from_lsp("textDocument/definition", arg)
    if req.kind ~= "ReqDefinition" then error("definition: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end

    local mod_at_pos = req.position and module_name_at_position(doc.text or "", req.position.line, req.position.character) or nil
    if mod_at_pos then
        local ml = self:_module_doc_locations(mod_at_pos)
        if #ml.items > 0 then return ml end
    end

    local base, field = nil, nil
    if req.position then
        base, field = field_access_at_position(doc.text or "", req.position.line, req.position.character)
    end
    if base and field then
        local aliases = require_alias_map(doc.text or "")
        local mod = aliases[base]
        if mod then
            local mfl = self:_workspace_module_field_locations(mod, field, true)
            if #mfl.items > 0 then return mfl end
        end
    end

    local subject = self:_resolve_subject(doc, req)
    if not subject then
        local guess = req.position and word_at_position(doc.text or "", req.position.line, req.position.character) or nil
        if guess and guess ~= "" then
            local ml = self:_module_doc_locations(guess)
            if #ml.items > 0 then return ml end
            local tlocs = self:_workspace_type_locations(guess)
            if #tlocs.items > 0 then return tlocs end
            return self:_workspace_global_locations(guess, true)
        end
        return C.LspLocationList({})
    end

    local local_hits = pvm.one(self.adapter:definition(doc, subject))
    if local_hits and #local_hits.items > 0 then
        return local_hits
    end

    if type(subject) == "string" then
        local ml = self:_module_doc_locations(subject)
        if #ml.items > 0 then return ml end
        local tlocs = self:_workspace_type_locations(subject)
        if #tlocs.items > 0 then return tlocs end
        return self:_workspace_global_locations(subject, true)
    end

    local binding = pvm.one(self.engine:symbol_for_anchor(doc, subject))
    if binding.kind == "AnchorSymbol" and binding.symbol.kind == C.SymGlobal then
        return self:_workspace_global_locations(binding.symbol.name, true)
    end
    if binding.kind == "AnchorUnresolved" then
        return self:_workspace_global_locations(binding.name, true)
    end

    local guess = req.position and word_at_position(doc.text or "", req.position.line, req.position.character) or nil
    if guess and guess ~= "" then
        local ml = self:_module_doc_locations(guess)
        if #ml.items > 0 then return ml end
        local tlocs = self:_workspace_type_locations(guess)
        if #tlocs.items > 0 then return tlocs end
        return self:_workspace_global_locations(guess, true)
    end

    return C.LspLocationList({})
end

function Core:declaration(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDeclaration") and arg or self:request_from_lsp("textDocument/declaration", arg)
    if req.kind ~= "ReqDeclaration" then error("declaration: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end

    local subject = self:_resolve_subject(doc, req)
    if not subject then
        return self:definition(C.ReqDefinition(req.doc, req.position, req.subject))
    end

    if type(subject) == "string" then
        local tlocs = self:_workspace_type_locations(subject)
        if #tlocs.items > 0 then return tlocs end
        return self:_workspace_global_locations(subject, true)
    end

    local binding = pvm.one(self.engine:symbol_for_anchor(doc, subject))
    if binding.kind == "AnchorSymbol" and binding.symbol then
        local sk = binding.symbol.kind
        if sk == C.SymTypeClass or sk == C.SymTypeAlias or sk == C.SymTypeGeneric then
            local tlocs = self:_workspace_type_locations(binding.symbol.name)
            if #tlocs.items > 0 then return tlocs end
        end

        local defs = pvm.drain(self.engine:definitions_of(doc, binding.symbol.id))
        local out, seen = {}, {}
        for i = 1, #defs do
            local occ = defs[i]
            if occ and occ.anchor then
                local r = self:_range_for(doc, occ.anchor)
                local key = req.doc.uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = C.LspLocation(req.doc.uri, r)
                end
            end
        end
        if #out > 0 then return C.LspLocationList(out) end
    end

    return self:definition(C.ReqDefinition(req.doc, req.position, req.subject))
end

function Core:implementation(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqImplementation") and arg or self:request_from_lsp("textDocument/implementation", arg)
    if req.kind ~= "ReqImplementation" then error("implementation: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end

    local seeds = {}
    local subject = self:_resolve_subject(doc, req)
    if type(subject) == "string" then
        seeds[#seeds + 1] = subject
    elseif subject then
        local binding = pvm.one(self.engine:symbol_for_anchor(doc, subject))
        if binding.kind == "AnchorSymbol" and binding.symbol then
            local sk = binding.symbol.kind
            if sk == C.SymTypeClass or sk == C.SymTypeAlias or sk == C.SymTypeGeneric then
                seeds[#seeds + 1] = binding.symbol.name
            elseif self._type_engine and self._workspace_engine then
                local names = self._workspace_engine:named_type_names(self._type_engine.type_for_anchor(doc, subject))
                for i = 1, #names do seeds[#seeds + 1] = names[i] end
            end
        end
    end

    if #seeds == 0 and req.position then
        local guess = word_at_position(doc.text or "", req.position.line, req.position.character)
        if guess and guess ~= "" then seeds[1] = guess end
    end

    local expanded = self:_expand_type_names(seeds)
    local out, dedupe = {}, {}
    for i = 1, #expanded do
        local impls = self:_workspace_type_implementations(expanded[i])
        for j = 1, #impls.items do
            local l = impls.items[j]
            local r = l.range
            local key = l.uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
            if not dedupe[key] then
                dedupe[key] = true
                out[#out + 1] = l
            end
        end
    end

    if #out > 0 then return C.LspLocationList(out) end
    return self:definition(C.ReqDefinition(req.doc, req.position, req.subject))
end

function Core:type_definition(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqTypeDefinition") and arg or self:request_from_lsp("textDocument/typeDefinition", arg)
    if req.kind ~= "ReqTypeDefinition" then error("type_definition: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end

    local seeds, seen = {}, {}
    local subject = self:_resolve_subject(doc, req)

    if type(subject) == "string" then
        seeds[#seeds + 1] = subject
        seen[subject] = true
    elseif subject then
        local binding = pvm.one(self.engine:symbol_for_anchor(doc, subject))
        if binding.kind == "AnchorSymbol" and binding.symbol then
            local sk = binding.symbol.kind
            if sk == C.SymTypeClass or sk == C.SymTypeAlias or sk == C.SymTypeGeneric then
                local n = binding.symbol.name
                seeds[#seeds + 1] = n
                seen[n] = true
            elseif self._type_engine and self._workspace_engine then
                local names = self._workspace_engine:named_type_names(self._type_engine.type_for_anchor(doc, subject))
                for i = 1, #names do
                    local n = names[i]
                    if not seen[n] then seen[n] = true; seeds[#seeds + 1] = n end
                end
            end
        elseif binding.kind == "AnchorUnresolved" and binding.name and binding.name ~= "" then
            seeds[#seeds + 1] = binding.name
            seen[binding.name] = true
        end
    end

    -- Method receiver typing: obj.field -> resolve obj type -> field type.
    if req.position then
        local base, field, bs = field_access_at_position(doc.text or "", req.position.line, req.position.character)
        if base and field and bs and self._type_engine then
            local line_start, line_end = line_bounds(doc.text or "", req.position.line)
            local line_text = (doc.text or ""):sub(line_start, line_end - 1)
            local base_char = byte_to_utf16_col_in_line(line_text, bs)
            local pick = pvm.one(self.adapter:anchor_at_position(doc, { line = req.position.line, character = base_char }, "use"))
            if pick and pick.kind == "AnchorPickHit" then
                local base_names = self._workspace_engine and self._workspace_engine:named_type_names(self._type_engine.type_for_anchor(doc, pick.anchor)) or {}
                local expanded_base = self:_expand_type_names(base_names)
                for i = 1, #expanded_base do
                    local fnames = self:_workspace_class_field_type_names(expanded_base[i], field)
                    for j = 1, #fnames do
                        local n = fnames[j]
                        if n and n ~= "" and not seen[n] then
                            seen[n] = true
                            seeds[#seeds + 1] = n
                        end
                    end
                end
            end
        end
    end

    if #seeds == 0 and req.position then
        local guess = word_at_position(doc.text or "", req.position.line, req.position.character)
        if guess and guess ~= "" then seeds[1] = guess end
    end

    local names = self:_expand_type_names(seeds)
    local out, dedupe = {}, {}
    for i = 1, #names do
        local locs = self:_workspace_type_locations(names[i])
        for j = 1, #locs.items do
            local l = locs.items[j]
            local r = l.range
            local key = l.uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
            if not dedupe[key] then
                dedupe[key] = true
                out[#out + 1] = l
            end
        end
    end

    return C.LspLocationList(out)
end

function Core:references(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqReferences") and arg or self:request_from_lsp("textDocument/references", arg)
    if req.kind ~= "ReqReferences" then error("references: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspLocationList({}) end
    local include_decl = req.context and req.context.include_declaration or false

    local mod_at_pos = req.position and module_name_at_position(doc.text or "", req.position.line, req.position.character) or nil
    if mod_at_pos then
        return self:_module_doc_locations(mod_at_pos)
    end

    local base, field = nil, nil
    if req.position then
        base, field = field_access_at_position(doc.text or "", req.position.line, req.position.character)
    end
    if base and field then
        local aliases = require_alias_map(doc.text or "")
        local mod = aliases[base]
        if mod then
            local mfl = self:_workspace_module_field_locations(mod, field, include_decl)
            if #mfl.items > 0 then return mfl end
        end
    end

    local subject = self:_resolve_subject(doc, req)
    if not subject then
        local guess = req.position and word_at_position(doc.text or "", req.position.line, req.position.character) or nil
        if guess and guess ~= "" then
            local ml = self:_module_doc_locations(guess)
            if #ml.items > 0 then return ml end
            return self:_workspace_global_locations(guess, include_decl)
        end
        return C.LspLocationList({})
    end

    local local_hits = pvm.one(self.adapter:references(doc, subject, include_decl))

    if type(subject) == "string" then
        local ws = self:_workspace_global_locations(subject, include_decl)
        if #ws.items > 0 then return ws end
        return local_hits
    end

    local binding = pvm.one(self.engine:symbol_for_anchor(doc, subject))
    if binding.kind == "AnchorSymbol" and binding.symbol.kind == C.SymGlobal then
        local ws = self:_workspace_global_locations(binding.symbol.name, include_decl)
        if #ws.items > 0 then return ws end
    elseif binding.kind == "AnchorUnresolved" then
        local ws = self:_workspace_global_locations(binding.name, include_decl)
        if #ws.items > 0 then return ws end
    end

    local guess = req.position and word_at_position(doc.text or "", req.position.line, req.position.character) or nil
    if guess and guess ~= "" then
        local ml = self:_module_doc_locations(guess)
        if #ml.items > 0 then return ml end
        local ws = self:_workspace_global_locations(guess, include_decl)
        if #ws.items > 0 then return ws end
    end

    return local_hits
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
    return pvm.one(self.adapter:document_highlight(doc, subject))
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
        return {
            range = self:to_lsp(v.range), severity = v.severity,
            source = v.source, code = v.code, message = v.message,
        }
    end
    if tag == "LspDiagnosticList" then
        local out = {}; for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end; return out
    end
    if tag == "LspDiagnosticReport" then
        local items = {}; for i = 1, #v.items do items[i] = self:to_lsp(v.items[i]) end
        local kk = tostring(v.kind):match("^Lua%.([%w_]+)") or ""
        local kind = (kk == "DiagReportUnchanged") and "unchanged" or "full"
        return { kind = kind, items = items, uri = v.uri, version = v.version }
    end

    if tag == "LspMarkupContent" then
        local kk = tostring(v.kind):match("^Lua%.([%w_]+)") or ""
        local kind = (kk == "MarkupMarkdown") and "markdown" or "plaintext"
        return { kind = kind, value = v.value }
    end
    if tag == "LspHover" then return { contents = self:to_lsp(v.contents), range = self:to_lsp(v.range) } end
    if tag == "LspHoverHit" then return self:to_lsp(v.value) end
    if tag == "LspHoverMiss" then return nil end

    if tag == "LspDocumentHighlight" then return { range = self:to_lsp(v.range), kind = v.kind } end
    if tag == "LspDocumentHighlightList" then
        local out = {}; for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end; return out
    end

    if tag == "LspCompletionItem" or tag == "CompletionItem" then
        local out = {
            label = v.label,
            kind = v.kind,
            detail = v.detail,
            sortText = v.sort_text,
            insertText = v.insert_text,
        }
        if v.documentation and v.documentation ~= "" then
            out.documentation = { kind = "plaintext", value = v.documentation }
        end
        return out
    end
    if tag == "LspCompletionList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return { isIncomplete = v.is_incomplete and true or false, items = out }
    end

    if tag == "LspDocumentSymbol" then
        local children = {}
        for i = 1, #v.children do children[i] = self:to_lsp(v.children[i]) end
        return {
            name = v.name,
            detail = v.detail,
            kind = v.kind,
            range = self:to_lsp(v.range),
            selectionRange = self:to_lsp(v.selection_range),
            children = children,
        }
    end
    if tag == "LspDocumentSymbolList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspSignatureInfo" then
        local prs = {}
        for i = 1, #v.param_ranges do
            local pr = v.param_ranges[i]
            prs[i] = {
                label = { pr.start.character, pr.stop.character },
            }
        end
        return {
            label = v.label,
            documentation = self:to_lsp(v.documentation),
            parameters = prs,
        }
    end
    if tag == "LspSignatureHelp" then
        local sigs = {}
        for i = 1, #v.signatures do sigs[i] = self:to_lsp(v.signatures[i]) end
        return {
            signatures = sigs,
            activeSignature = v.active_signature,
            activeParameter = v.active_parameter,
        }
    end

    if tag == "LspTextEdit" then
        return { range = self:to_lsp(v.range), newText = v.new_text }
    end
    if tag == "LspTextEditList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end
    if tag == "LspWorkspaceEdit" then
        local edits = {}
        for i = 1, #v.edits do edits[i] = self:to_lsp(v.edits[i]) end
        return { changes = { [v.uri] = edits } }
    end

    if tag == "LspFoldingRange" then
        local kk = tostring(v.kind):match("^Lua%.([%w_]+)%(") or ""
        local kind = "region"
        if kk == "FoldComment" then kind = "comment"
        elseif kk == "FoldImports" then kind = "imports" end
        return {
            startLine = v.start_line,
            startCharacter = v.start_character,
            endLine = v.end_line,
            endCharacter = v.end_character,
            kind = kind,
        }
    end
    if tag == "LspFoldingRangeList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspSelectionRange" then
        local node = { range = self:to_lsp(v.range) }
        local cur = node
        for i = 1, #v.parents do
            local p = { range = self:to_lsp(v.parents[i]) }
            cur.parent = p
            cur = p
        end
        return node
    end
    if tag == "LspSelectionRangeList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspCodeLens" then
        local cmd = nil
        if v.command_id and v.command_id ~= "" then
            cmd = { title = (v.command_title ~= "" and v.command_title) or v.command_id, command = v.command_id }
        end
        return { range = self:to_lsp(v.range), command = cmd }
    end
    if tag == "LspCodeLensList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspColor" then
        return { red = v.red, green = v.green, blue = v.blue, alpha = v.alpha }
    end
    if tag == "LspColorInfo" then
        return { range = self:to_lsp(v.range), color = self:to_lsp(v.color) }
    end
    if tag == "LspColorInfoList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspCodeAction" then
        local k = tostring(v.kind):match("^Lua%.([%w_]+)%(") or ""
        local kind = "quickfix"
        if k == "CodeActionRefactor" then kind = "refactor"
        elseif k == "CodeActionSource" then kind = "source" end
        return {
            title = v.title,
            kind = kind,
            edit = self:to_lsp(v.edit),
        }
    end
    if tag == "LspCodeActionList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspSemanticTokens" then
        return { data = v.data }
    end

    if tag == "LspInlayHint" then
        local k = tostring(v.kind):match("^Lua%.([%w_]+)%(") or ""
        local kind = (k == "InlayParameter") and 2 or 1
        return {
            position = self:to_lsp(v.position),
            label = v.label,
            kind = kind,
        }
    end
    if tag == "LspInlayHintList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspWorkspaceSymbol" then
        return {
            name = v.name,
            kind = v.kind,
            location = { uri = v.uri, range = self:to_lsp(v.range) },
            containerName = (v.container_name ~= "" and v.container_name) or nil,
        }
    end
    if tag == "LspWorkspaceSymbolList" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return out
    end

    if tag == "LspWorkspaceDiagnosticItem" then
        local items = {}
        for i = 1, #v.items do items[i] = self:to_lsp(v.items[i]) end
        local kk = tostring(v.kind):match("^Lua%.([%w_]+)") or ""
        local kind = (kk == "WsDiagUnchanged") and "unchanged" or "full"
        return { kind = kind, uri = v.uri, version = v.version, items = items }
    end
    if tag == "LspWorkspaceDiagnostic" then
        local out = {}
        for i = 1, #v.items do out[i] = self:to_lsp(v.items[i]) end
        return { items = out }
    end

    return v
end

function Core:completion(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCompletion") and arg or self:request_from_lsp("textDocument/completion", arg)
    if req.kind ~= "ReqCompletion" then error("completion: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._complete_engine then return C.LspCompletionList({}, false) end

    -- Figure out identifier prefix right before the cursor.
    local prefix = ""
    do
        local text = doc.text or ""
        local line0 = req.position and req.position.line or 0
        local char0 = req.position and req.position.character or 0
        local line_start, line_end = line_bounds(text, line0)
        if line_start <= #text + 1 then
            local line_text = text:sub(line_start, line_end - 1)
            local byte_col = utf16_col_to_byte_in_line(line_text, char0)
            if byte_col < 1 then byte_col = 1 end
            if byte_col > #line_text + 1 then byte_col = #line_text + 1 end
            local before = line_text:sub(1, byte_col - 1)
            prefix = before:match("([%w_]+)$") or ""
        end
    end

    local items = pvm.drain(self._complete_engine.complete(C.CompletionQuery(doc, req.position, prefix)))
    local out = {}
    for i = 1, #items do
        local it = items[i]
        out[i] = C.LspCompletionItem(it.label, it.kind, it.detail or "", it.sort_text or "", it.insert_text or it.label, "")
    end
    return C.LspCompletionList(out, false)
end

function Core:completion_resolve(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCompletionResolve") and arg or self:request_from_lsp("completionItem/resolve", arg)
    if req.kind ~= "ReqCompletionResolve" then error("completion_resolve: invalid request", 2) end

    local it = req.item
    if it.detail and it.detail ~= "" then return it end

    local label = it.label or ""
    local defs, uses = 0, 0
    local docs = self.docs.docs
    for i = 1, #docs do
        local idx = self.engine:index(docs[i])
        for j = 1, #idx.defs do if idx.defs[j].name == label then defs = defs + 1 end end
        for j = 1, #idx.uses do if idx.uses[j].name == label then uses = uses + 1 end end
    end

    local detail = (defs > 0 or uses > 0)
        and ("resolved symbol (defs=" .. defs .. ", refs=" .. uses .. ")")
        or "resolved item"
    local documentation = "symbol: " .. label
    return C.LspCompletionItem(it.label, it.kind, detail, it.sort_text, it.insert_text, documentation)
end

function Core:document_symbol(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDocumentSymbol") and arg or self:request_from_lsp("textDocument/documentSymbol", arg)
    if req.kind ~= "ReqDocumentSymbol" then error("document_symbol: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._docsymbols_engine then return C.LspDocumentSymbolList({}) end

    local default_range = C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
    local function range_for(anchor)
        if self.adapter and self.adapter._lsp_range_for and anchor then
            return pvm.one(self.adapter._lsp_range_for(C.LspRangeQuery(doc, anchor)))
        end
        return default_range
    end

    local function convert(sym)
        local children = {}
        for i = 1, #sym.children do
            children[i] = convert(sym.children[i])
        end
        local range = range_for(sym.anchor)
        return C.LspDocumentSymbol(sym.name, sym.detail or "", sym.kind, range, range, children)
    end

    local tree = pvm.one(self._docsymbols_engine.doc_symbol_tree(doc))
    local out = {}
    for i = 1, #tree.items do out[i] = convert(tree.items[i]) end
    return C.LspDocumentSymbolList(out)
end

function Core:signature_help(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSignatureHelp") and arg or self:request_from_lsp("textDocument/signatureHelp", arg)
    if req.kind ~= "ReqSignatureHelp" then error("signature_help: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc or not self._sighelp_engine then return C.LspSignatureHelp({}, 0, 0) end

    local callee, active_param = signature_context_at_position(doc.text or "", req.position.line, req.position.character)
    if not callee or callee == "" then return C.LspSignatureHelp({}, 0, 0) end

    local raw = pvm.one(self._sighelp_engine.signature_lookup(C.SignatureLookupQuery(doc, callee, active_param or 0)))

    if (not raw or #raw.signatures == 0) then
        local base, field = callee:match("^([%a_][%w_]*)[%.:]([%a_][%w_]*)$")
        if base and field then
            local aliases = require_alias_map(doc.text or "")
            local mod = aliases[base]
            if mod then
                local md = self:_module_docs_for_name(mod)
                local merged, seen = {}, {}
                for i = 1, #md do
                    local sub = pvm.one(self._sighelp_engine.signature_lookup(
                        C.SignatureLookupQuery(md[i], field, active_param or 0)
                    ))
                    for j = 1, #sub.signatures do
                        local s = sub.signatures[j]
                        if not seen[s.label] then
                            seen[s.label] = true
                            merged[#merged + 1] = s
                        end
                    end
                end
                if #merged > 0 then raw = C.SignatureHelp(merged, 0) end
            end
        end
    end

    if not raw or #raw.signatures == 0 then
        return C.LspSignatureHelp({}, 0, 0)
    end

    local sigs = {}
    for i = 1, #raw.signatures do
        local s = raw.signatures[i]
        local prs = {}
        local lp = s.label:find("(", 1, true)
        local offset = lp and utf16_len(s.label:sub(1, lp)) or 0
        for pi = 1, #s.params do
            local ptxt = s.params[pi].label or ""
            local startc = offset
            local stopc = startc + utf16_len(ptxt)
            prs[pi] = C.LspRange(C.LspPos(0, startc), C.LspPos(0, stopc))
            offset = stopc + utf16_len(", ")
        end
        sigs[i] = C.LspSignatureInfo(
            s.label,
            C.LspMarkupContent(C.MarkupPlainText, "inferred"),
            prs
        )
    end

    local ap = raw.signatures[1].active_param or 0
    if ap < 0 then ap = 0 end
    return C.LspSignatureHelp(sigs, raw.active_signature or 0, ap)
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
    return pvm.one(self._rename_engine.rename(C.RenameQuery(doc, anchor, req.new_name)))
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
    return pvm.one(self._rename_engine.prepare_rename(
        C.RenameQuery(doc, anchor, "")))
end

function Core:code_action(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCodeAction") and arg or self:request_from_lsp("textDocument/codeAction", arg)
    if req.kind ~= "ReqCodeAction" then error("code_action: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc or not self._codeaction_engine then return C.LspCodeActionList({}) end

    local report = self:diagnostic(C.ReqDiagnostic(C.LspDocIdentifier(doc.uri)))
    local q = C.CodeActionQuery(doc, doc.uri, req.range, report.items or {})
    return pvm.one(self._codeaction_engine.plan_code_actions(q))
end

function Core:code_action_resolve(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCodeActionResolve") and arg or self:request_from_lsp("codeAction/resolve", arg)
    if req.kind ~= "ReqCodeActionResolve" then error("code_action_resolve: invalid request", 2) end

    local a = req.action
    local edit = a.edit or C.LspWorkspaceEdit({}, "")
    local n = #(edit.edits or {})
    local title = a.title or ""
    if n > 0 and not title:match("%(%d+ edits?%)$") then
        title = title .. " (" .. n .. " edit" .. (n == 1 and "" or "s") .. ")"
    end
    return C.LspCodeAction(title, a.kind, edit)
end

local function encode_semantic_tokens(C, spans)
    local tok_index = {
        [C.SemTokNamespace] = 0,
        [C.SemTokType] = 1,
        [C.SemTokClass] = 2,
        [C.SemTokEnum] = 3,
        [C.SemTokInterface] = 4,
        [C.SemTokStruct] = 5,
        [C.SemTokTypeParameter] = 6,
        [C.SemTokParameter] = 7,
        [C.SemTokVariable] = 8,
        [C.SemTokProperty] = 9,
        [C.SemTokEnumMember] = 10,
        [C.SemTokEvent] = 11,
        [C.SemTokFunction] = 12,
        [C.SemTokMethod] = 13,
        [C.SemTokMacro] = 14,
        [C.SemTokKeyword] = 15,
        [C.SemTokModifier] = 16,
        [C.SemTokComment] = 17,
        [C.SemTokString] = 18,
        [C.SemTokNumber] = 19,
        [C.SemTokRegexp] = 20,
        [C.SemTokOperator] = 21,
        [C.SemTokDecorator] = 22,
    }

    local mod_bit = {
        [C.SemTokDeclaration] = 1,
        [C.SemTokDefinition] = 2,
        [C.SemTokReadonly] = 4,
        [C.SemTokStatic] = 8,
        [C.SemTokDeprecated] = 16,
        [C.SemTokAbstract] = 32,
        [C.SemTokAsync] = 64,
        [C.SemTokModification] = 128,
        [C.SemTokDocumentation] = 256,
        [C.SemTokDefaultLibrary] = 512,
        [C.SemTokGlobal] = 1024,
    }

    local data = {}
    local prev_line, prev_start = 0, 0
    for i = 1, #spans do
        local t = spans[i]
        local dl = t.line - prev_line
        local ds = (dl == 0) and (t.start - prev_start) or t.start
        data[#data + 1] = dl
        data[#data + 1] = ds
        data[#data + 1] = t.length
        data[#data + 1] = tok_index[t.token_type] or tok_index[C.SemTokVariable]

        local bits = 0
        for m = 1, #t.token_modifiers do
            bits = bits + (mod_bit[t.token_modifiers[m]] or 0)
        end
        data[#data + 1] = bits

        prev_line, prev_start = t.line, t.start
    end

    return C.LspSemanticTokens(data)
end

function Core:semantic_tokens_full(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSemanticTokensFull") and arg or self:request_from_lsp("textDocument/semanticTokens/full", arg)
    if req.kind ~= "ReqSemanticTokensFull" then error("semantic_tokens_full: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc or not self._semtokens_engine then return C.LspSemanticTokens({}) end

    local spans = pvm.one(self._semtokens_engine.plan_semantic_tokens(
        C.LspSemanticTokenQuery(doc)
    )).items

    return encode_semantic_tokens(C, spans)
end

function Core:semantic_tokens_range(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSemanticTokensRange") and arg or self:request_from_lsp("textDocument/semanticTokens/range", arg)
    if req.kind ~= "ReqSemanticTokensRange" then error("semantic_tokens_range: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc or not self._semtokens_engine then return C.LspSemanticTokens({}) end

    local src = pvm.one(self._semtokens_engine.plan_semantic_tokens(
        C.LspSemanticTokenQuery(doc)
    )).items

    local out = {}
    local sline, eline = req.range.start.line, req.range.stop.line
    for i = 1, #src do
        local t = src[i]
        if t.line >= sline and t.line <= eline then out[#out + 1] = t end
    end
    return encode_semantic_tokens(C, out)
end

function Core:inlay_hint(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqInlayHint") and arg or self:request_from_lsp("textDocument/inlayHint", arg)
    if req.kind ~= "ReqInlayHint" then error("inlay_hint: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspInlayHintList({}) end
    if self._editor_engine then
        return pvm.one(self._editor_engine.inlay_hints(C.InlayHintQuery(doc, req.range)))
    end
    return C.LspInlayHintList({})
end

function Core:formatting(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqFormatting") and arg or self:request_from_lsp("textDocument/formatting", arg)
    if req.kind ~= "ReqFormatting" then error("formatting: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspTextEditList({}) end

    local opts = req.options or C.LspFormattingOptions(4, true, true, true)

    local fr = nil
    if self._format_engine and self._format_engine.format_file then
        fr = pvm.one(self._format_engine.format_file(C.FormatQuery(doc, opts, req.range, req.has_range)))
    end

    if not fr then
        local fallback = simple_format_text(doc.text or "", opts.tab_size, opts.insert_spaces)
        fr = C.FormatResult(fallback, C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0)), false)
    end

    if fr.has_range then
        local s = fr.range.start
        local e = fr.range.stop
        local from = line_utf16_to_offset(doc.text or "", s.line, s.character)
        local to = line_utf16_to_offset(doc.text or "", e.line, e.character)
        if to < from then to = from end
        local current = (doc.text or ""):sub(from, to - 1)
        if current == fr.text then return C.LspTextEditList({}) end
        return C.LspTextEditList({ C.LspTextEdit(fr.range, fr.text) })
    end

    if fr.text == (doc.text or "") then return C.LspTextEditList({}) end
    return C.LspTextEditList({
        C.LspTextEdit(whole_text_range(C, doc.text or ""), fr.text)
    })
end

function Core:folding_range(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqFoldingRange") and arg or self:request_from_lsp("textDocument/foldingRange", arg)
    if req.kind ~= "ReqFoldingRange" then error("folding_range: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspFoldingRangeList({}) end
    if self._editor_engine then
        return pvm.one(self._editor_engine.folding_ranges(C.FoldingRangeQuery(doc)))
    end
    return C.LspFoldingRangeList({})
end

function Core:selection_range(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSelectionRange") and arg or self:request_from_lsp("textDocument/selectionRange", arg)
    if req.kind ~= "ReqSelectionRange" then error("selection_range: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspSelectionRangeList({}) end
    if self._editor_engine then
        return pvm.one(self._editor_engine.selection_ranges(C.SelectionRangeQuery(doc, req.positions)))
    end
    return C.LspSelectionRangeList({})
end

function Core:code_lens(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCodeLens") and arg or self:request_from_lsp("textDocument/codeLens", arg)
    if req.kind ~= "ReqCodeLens" then error("code_lens: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspCodeLensList({}) end
    if self._editor_engine then
        return pvm.one(self._editor_engine.code_lenses(C.CodeLensQuery(doc)))
    end
    return C.LspCodeLensList({})
end

function Core:document_color(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDocumentColor") and arg or self:request_from_lsp("textDocument/documentColor", arg)
    if req.kind ~= "ReqDocumentColor" then error("document_color: invalid request", 2) end
    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspColorInfoList({}) end
    if self._editor_engine then
        return pvm.one(self._editor_engine.document_colors(C.ColorQuery(doc)))
    end
    return C.LspColorInfoList({})
end

function Core:execute_command(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqExecuteCommand") and arg or self:request_from_lsp("workspace/executeCommand", arg)
    if req.kind ~= "ReqExecuteCommand" then error("execute_command: invalid request", 2) end
    if req.command == "lua.removeSpace" or req.command == "lua.solve"
        or req.command == "lua.jsonToLua" or req.command == "lua.setConfig"
        or req.command == "lua.getConfig" or req.command == "lua.autoRequire" then
        return "ok"
    end
    return "unsupported"
end

function Core:workspace_symbol(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqWorkspaceSymbol") and arg or self:request_from_lsp("workspace/symbol", arg)
    if req.kind ~= "ReqWorkspaceSymbol" then error("workspace_symbol: invalid request", 2) end
    if self._workspace_engine then
        return self._workspace_engine:workspace_symbols(self.docs, req.query or "")
    end
    return C.LspWorkspaceSymbolList({})
end

function Core:workspace_diagnostic(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqWorkspaceDiagnostic") and arg or self:request_from_lsp("workspace/diagnostic", arg)
    if req.kind ~= "ReqWorkspaceDiagnostic" then error("workspace_diagnostic: invalid request", 2) end
    if self._workspace_engine then
        return self._workspace_engine:workspace_diagnostics(self.docs)
    end
    return C.LspWorkspaceDiagnostic({})
end

function Core:handle_request(req)
    local k = req and req.kind
    if k == "ReqDidOpen" then self:did_open(req); return nil end
    if k == "ReqDidChange" then self:did_change(req); return nil end
    if k == "ReqDidClose" then self:did_close(req); return nil end
    if k == "ReqDidSave" then self:did_save(req); return nil end
    if k == "ReqHover" then return self:hover(req) end
    if k == "ReqDefinition" then return self:definition(req) end
    if k == "ReqDeclaration" then return self:declaration(req) end
    if k == "ReqImplementation" then return self:implementation(req) end
    if k == "ReqTypeDefinition" then return self:type_definition(req) end
    if k == "ReqReferences" then return self:references(req) end
    if k == "ReqDocumentHighlight" then return self:document_highlight(req) end
    if k == "ReqDiagnostic" then return self:diagnostic(req) end
    if k == "ReqCompletion" then return self:completion(req) end
    if k == "ReqCompletionResolve" then return self:completion_resolve(req) end
    if k == "ReqDocumentSymbol" then return self:document_symbol(req) end
    if k == "ReqSignatureHelp" then return self:signature_help(req) end
    if k == "ReqRename" then return self:rename(req) end
    if k == "ReqPrepareRename" then return self:prepare_rename(req) end
    if k == "ReqCodeAction" then return self:code_action(req) end
    if k == "ReqCodeActionResolve" then return self:code_action_resolve(req) end
    if k == "ReqSemanticTokensFull" then return self:semantic_tokens_full(req) end
    if k == "ReqSemanticTokensRange" then return self:semantic_tokens_range(req) end
    if k == "ReqInlayHint" then return self:inlay_hint(req) end
    if k == "ReqFormatting" then return self:formatting(req) end
    if k == "ReqFoldingRange" then return self:folding_range(req) end
    if k == "ReqSelectionRange" then return self:selection_range(req) end
    if k == "ReqCodeLens" then return self:code_lens(req) end
    if k == "ReqDocumentColor" then return self:document_color(req) end
    if k == "ReqWorkspaceSymbol" then return self:workspace_symbol(req) end
    if k == "ReqWorkspaceDiagnostic" then return self:workspace_diagnostic(req) end
    if k == "ReqExecuteCommand" then return self:execute_command(req) end
    if k == "ReqInvalid" then error(tostring(req.reason or "invalid request"), 2) end
    error("invalid request kind", 2)
end

function Core:handle_lsp(method, params) return self:to_lsp(self:handle(method, params)) end
function Core:handle(method, params) return self:handle_request(self:request_from_lsp(method, params)) end

return { new = function(opts) return Core.new(opts) end }
