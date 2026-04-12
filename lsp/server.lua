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

local function pos_leq(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.character <= b.character
end

local function position_in_range(pos, r)
    if not pos or not r or not r.start or not r.stop then return false end
    return pos_leq(r.start, pos) and pos_leq(pos, r.stop)
end

local function range_size_key(r)
    if not r or not r.start or not r.stop then return math.huge end
    local dl = (r.stop.line or 0) - (r.start.line or 0)
    local dc = (r.stop.character or 0) - (r.start.character or 0)
    if dc < 0 then dc = 0 end
    return dl * 100000 + dc
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

local function split_lines(text)
    local raw_lines = {}
    local n = 0
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        raw_lines[n] = line
    end
    if n > 0 then n = n - 1 end -- drop synthetic split line
    return raw_lines, n
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
    if type(e) == "table" and type(e.changes) == "table" then
        for uri, arr in pairs(e.changes) do
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
            edit = C.LspWorkspaceEdit(edits, tostring(uri or ""))
            break
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

local function ws_symbol_kind(sk)
    if sk == nil then return 13 end
    local k = tostring(sk):match("^Lua%.([%w_]+)") or ""
    if k == "SymBuiltin" then return 12 end
    if k == "SymTypeClass" then return 5 end
    if k == "SymTypeGeneric" then return 26 end
    return 13
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

function Core:_range_for(file, anchor)
    local C = self.engine.C
    if self.adapter and self.adapter._lsp_range_for and file and anchor then
        return self.adapter._lsp_range_for(C.LspRangeQuery(file, anchor))
    end
    return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
end

function Core:_workspace_global_locations(name, include_declaration)
    local C = self.engine.C
    local out, seen = {}, {}
    local docs = self.docs.docs

    local function add(uri, file, anchor)
        if not uri or not file or not anchor then return end
        local r = self:_range_for(file, anchor)
        local key = uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspLocation(uri, r)
    end

    for i = 1, #docs do
        local d = docs[i]
        local idx = self.engine:index(d.file)
        if include_declaration then
            for j = 1, #idx.defs do
                local occ = idx.defs[j]
                if occ.name == name and occ.kind == C.SymGlobal then
                    add(d.uri, d.file, occ.anchor)
                end
            end
        end
        for j = 1, #idx.uses do
            local occ = idx.uses[j]
            if occ.name == name and occ.kind == C.SymGlobal then
                add(d.uri, d.file, occ.anchor)
            end
        end
        for j = 1, #idx.unresolved do
            local occ = idx.unresolved[j]
            if occ.name == name then
                add(d.uri, d.file, occ.anchor)
            end
        end
    end

    return C.LspLocationList(out)
end

local function collect_named_from_typeexpr(t, out, seen)
    if not t or type(t) ~= "table" then return end
    local k = t.kind
    if k == "TNamed" then
        local nm = t.name
        if nm and nm ~= "" and not seen[nm] then
            seen[nm] = true
            out[#out + 1] = nm
        end
        return
    end
    if k == "TOptional" then return collect_named_from_typeexpr(t.inner, out, seen) end
    if k == "TArray" then return collect_named_from_typeexpr(t.item, out, seen) end
    if k == "TMap" then
        collect_named_from_typeexpr(t.key, out, seen)
        collect_named_from_typeexpr(t.value, out, seen)
        return
    end
    if k == "TTuple" then
        for i = 1, #t.items do collect_named_from_typeexpr(t.items[i], out, seen) end
        return
    end
    if k == "TUnion" then
        for i = 1, #t.parts do collect_named_from_typeexpr(t.parts[i], out, seen) end
        return
    end
    if k == "TTable" then
        for i = 1, #t.fields do collect_named_from_typeexpr(t.fields[i].typ, out, seen) end
        return
    end
    if k == "TFunc" and t.sig then
        for i = 1, #t.sig.params do collect_named_from_typeexpr(t.sig.params[i], out, seen) end
        for i = 1, #t.sig.returns do collect_named_from_typeexpr(t.sig.returns[i], out, seen) end
        return
    end
end

function Core:_workspace_type_target(name)
    local docs = self.docs.docs
    for i = 1, #docs do
        local d = docs[i]
        local tt = self.engine:type_target(d.file, name)
        if tt and tt.kind ~= "TypeTargetMissing" then return tt end
    end
    return nil
end

function Core:_expand_type_names(seed)
    local out, seen = {}, {}
    local q = {}
    for i = 1, #seed do
        local n = seed[i]
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
            q[#q + 1] = n
        end
    end

    local qi = 1
    while qi <= #q and qi <= 64 do
        local n = q[qi]; qi = qi + 1
        local tt = self:_workspace_type_target(n)
        if tt and tt.kind == "TypeAliasTarget" and tt.value and tt.value.typ then
            local names = {}
            collect_named_from_typeexpr(tt.value.typ, names, {})
            for i = 1, #names do
                local nm = names[i]
                if not seen[nm] then
                    seen[nm] = true
                    out[#out + 1] = nm
                    q[#q + 1] = nm
                end
            end
        end
    end

    return out
end

function Core:_workspace_type_locations(name)
    local C = self.engine.C
    local out, seen = {}, {}
    local docs = self.docs.docs

    local function add(uri, file, anchor)
        if not uri or not file or not anchor then return end
        local r = self:_range_for(file, anchor)
        local key = uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspLocation(uri, r)
    end

    for i = 1, #docs do
        local d = docs[i]
        local tt = self.engine:type_target(d.file, name)
        if tt and tt.kind ~= "TypeTargetMissing" and tt.anchor then
            add(d.uri, d.file, tt.anchor)
        end
    end

    return C.LspLocationList(out)
end

function Core:_workspace_class_field_type_names(class_name, field_name)
    local out, seen = {}, {}
    local docs = self.docs.docs

    local function expr_terminal_name(e)
        if not e or type(e) ~= "table" then return nil end
        if e.kind == "NameRef" then return e.name end
        if e.kind == "Field" then return e.key end
        return nil
    end

    local function collect_return_names_from_item(item)
        for d = 1, #item.docs do
            local tags = item.docs[d].tags
            for t = 1, #tags do
                if tags[t].kind == "ReturnTag" then
                    for r = 1, #tags[t].values do
                        collect_named_from_typeexpr(tags[t].values[r], out, seen)
                    end
                end
            end
        end
    end

    local function gather_for_class(cname, visited)
        if not cname or cname == "" then return end
        visited = visited or {}
        if visited[cname] then return end
        visited[cname] = true

        for i = 1, #docs do
            local d = docs[i]
            local env = self.engine.resolve_named_types(d.file)

            for j = 1, #env.classes do
                local cls = env.classes[j]
                if cls.name == cname then
                    for k = 1, #cls.fields do
                        local f = cls.fields[k]
                        if f.name == field_name then
                            collect_named_from_typeexpr(f.typ, out, seen)
                        end
                    end
                    for k = 1, #cls.extends do
                        local ex = cls.extends[k]
                        if ex and ex.kind == "TNamed" and ex.name then
                            gather_for_class(ex.name, visited)
                        end
                    end
                end
            end

            for j = 1, #d.file.items do
                local item = d.file.items[j]
                local s = item.stmt
                if s and s.kind == "Function" and s.name and (s.name.kind == "LMethod" or s.name.kind == "LField") then
                    local base_name = expr_terminal_name(s.name.base)
                    local member = (s.name.kind == "LMethod") and s.name.method or s.name.key
                    if base_name == cname and member == field_name then
                        collect_return_names_from_item(item)
                    end
                end
            end
        end
    end

    gather_for_class(class_name, {})
    return out
end

function Core:_workspace_type_implementations(name)
    local C = self.engine.C
    local out, seen = {}, {}
    local docs = self.docs.docs

    local function add(uri, file, anchor)
        if not uri or not file or not anchor then return end
        local r = self:_range_for(file, anchor)
        local key = uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspLocation(uri, r)
    end

    for i = 1, #docs do
        local d = docs[i]
        local env = self.engine.resolve_named_types(d.file)
        for j = 1, #env.classes do
            local cls = env.classes[j]
            for k = 1, #cls.extends do
                local ex = cls.extends[k]
                if type(ex) == "table" and ex.kind == "TNamed" and ex.name == name then
                    add(d.uri, d.file, cls.anchor)
                    break
                end
            end
        end
    end

    return C.LspLocationList(out)
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
    local C = self.engine.C
    local docs = self:_module_docs_for_name(name)
    local out = {}
    for i = 1, #docs do
        out[#out + 1] = C.LspLocation(
            docs[i].uri,
            C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
        )
    end
    return C.LspLocationList(out)
end

function Core:_workspace_module_field_locations(module_name, field, include_declaration)
    local C = self.engine.C
    local mod = normalize_module_name(module_name)
    local fname = tostring(field or "")
    if mod == nil or mod == "" or fname == "" then return C.LspLocationList({}) end

    local out, seen = {}, {}

    local function add(uri, line, scol, ecol)
        local key = uri .. ":" .. line .. ":" .. scol .. ":" .. ecol
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspLocation(uri,
            C.LspRange(C.LspPos(line, scol), C.LspPos(line, ecol)))
    end

    local module_docs = self:_module_docs_for_name(mod)
    local module_set = {}
    for i = 1, #module_docs do module_set[module_docs[i].uri] = true end

    -- Declarations/definitions inside module files.
    if include_declaration then
        for i = 1, #module_docs do
            local d = module_docs[i]
            local text = d.text or ""

            local module_vars = {}
            for v in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*{}") do module_vars[v] = true end
            for v in text:gmatch("return%s+([%a_][%w_]*)") do module_vars[v] = true end

            local line_no = 0
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
                for v in pairs(module_vars) do
                    local p1 = "^%s*" .. v .. "%.(" .. fname .. ")%s*="
                    local p2 = "^%s*function%s+" .. v .. "[:%.](" .. fname .. ")"
                    if line:match(p1) or line:match(p2) then
                        local fs = line:find(fname, 1, true)
                        if fs then add(d.uri, line_no, fs - 1, fs - 1 + #fname) end
                    end
                end
                line_no = line_no + 1
            end
        end
    end

    -- References in files that require this module.
    local docs = self.docs.docs
    for i = 1, #docs do
        local d = docs[i]
        local aliases = require_alias_map(d.text or "")
        local alias_list = {}
        for a, m in pairs(aliases) do
            if m == mod then alias_list[#alias_list + 1] = a end
        end
        if #alias_list > 0 then
            local line_no = 0
            for line in ((d.text or "") .. "\n"):gmatch("([^\n]*)\n") do
                for j = 1, #alias_list do
                    local a = alias_list[j]
                    local s, e = line:find(a .. "%s*[%.:]%s*" .. fname)
                    if s then
                        local fs = line:find(fname, s, true)
                        if fs then add(d.uri, line_no, fs - 1, fs - 1 + #fname) end
                    end
                end
                line_no = line_no + 1
            end
        end
    end

    return C.LspLocationList(out)
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
        return C.ReqWorkspaceDiagnostic()
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
    if #req.changes > 0 then
        for i = 1, #req.changes do
            next_text = apply_lsp_change(next_text, req.changes[i])
        end
    end
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
    local ds = self.adapter:diagnostics(doc.file).items
    for i = 1, #ds do items[i] = ds[i] end
    if doc.meta and doc.meta.parse_error and doc.meta.parse_error ~= "" then
        items[#items + 1] = C.LspDiagnostic(
            C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)), 1,
            "lua-lsp-pvm", "parse-error", tostring(doc.meta.parse_error))
    end
    return C.LspDiagnosticReport(C.DiagReportFull, items, doc.uri, doc.version or 0)
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

    local local_hits = self.adapter:definition(doc.file, subject)
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

    local binding = self.engine:symbol_for_anchor(doc.file, subject)
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

    local binding = self.engine:symbol_for_anchor(doc.file, subject)
    if binding.kind == "AnchorSymbol" and binding.symbol then
        local sk = binding.symbol.kind
        if sk == C.SymTypeClass or sk == C.SymTypeAlias or sk == C.SymTypeGeneric then
            local tlocs = self:_workspace_type_locations(binding.symbol.name)
            if #tlocs.items > 0 then return tlocs end
        end

        local defs = self.engine:definitions_of(doc.file, binding.symbol.id)
        local out, seen = {}, {}
        for i = 1, #(defs.items or {}) do
            local occ = defs.items[i]
            if occ and occ.anchor then
                local r = self:_range_for(doc.file, occ.anchor)
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
        local binding = self.engine:symbol_for_anchor(doc.file, subject)
        if binding.kind == "AnchorSymbol" and binding.symbol then
            local sk = binding.symbol.kind
            if sk == C.SymTypeClass or sk == C.SymTypeAlias or sk == C.SymTypeGeneric then
                seeds[#seeds + 1] = binding.symbol.name
            elseif self._type_engine then
                collect_named_from_typeexpr(self._type_engine.type_for_anchor(doc.file, subject), seeds, {})
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
        local binding = self.engine:symbol_for_anchor(doc.file, subject)
        if binding.kind == "AnchorSymbol" and binding.symbol then
            local sk = binding.symbol.kind
            if sk == C.SymTypeClass or sk == C.SymTypeAlias or sk == C.SymTypeGeneric then
                local n = binding.symbol.name
                seeds[#seeds + 1] = n
                seen[n] = true
            elseif self._type_engine then
                collect_named_from_typeexpr(self._type_engine.type_for_anchor(doc.file, subject), seeds, seen)
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
            local pick = self.adapter:anchor_at_position(doc.file, { line = req.position.line, character = base_char }, "use")
            if pick and pick.kind == "AnchorPickHit" then
                local base_names = {}
                collect_named_from_typeexpr(self._type_engine.type_for_anchor(doc.file, pick.anchor), base_names, {})
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

    local local_hits = self.adapter:references(doc.file, subject, include_decl)

    if type(subject) == "string" then
        local ws = self:_workspace_global_locations(subject, include_decl)
        if #ws.items > 0 then return ws end
        return local_hits
    end

    local binding = self.engine:symbol_for_anchor(doc.file, subject)
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
    if tag == "LspCompletionList" or tag == "CompletionList" then
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

    local raw = self._complete_engine.complete(C.CompletionQuery(doc.file, req.position, prefix))
    if raw.kind == "LspCompletionList" then
        return raw
    end

    local out = {}
    local items = raw.items or {}
    for i = 1, #items do
        local it = items[i]
        out[i] = C.LspCompletionItem(it.label, it.kind, it.detail or "", it.sort_text or "", it.insert_text or it.label, "")
    end
    return C.LspCompletionList(out, raw.is_incomplete and true or false)
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
        local idx = self.engine:index(docs[i].file)
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
            return self.adapter._lsp_range_for(C.LspRangeQuery(doc.file, anchor))
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

    local raw = pvm.drain(self._docsymbols_engine.doc_symbols(doc.file))
    local out = {}
    for i = 1, #raw do out[i] = convert(raw[i]) end
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

    local raw = self._sighelp_engine.signature_lookup(C.SignatureLookupQuery(doc.file, callee, active_param or 0))

    if (not raw or #raw.signatures == 0) then
        local base, field = callee:match("^([%a_][%w_]*)[%.:]([%a_][%w_]*)$")
        if base and field then
            local aliases = require_alias_map(doc.text or "")
            local mod = aliases[base]
            if mod then
                local md = self:_module_docs_for_name(mod)
                local merged, seen = {}, {}
                for i = 1, #md do
                    local sub = self._sighelp_engine.signature_lookup(
                        C.SignatureLookupQuery(md[i].file, field, active_param or 0)
                    )
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

function Core:code_action(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCodeAction") and arg or self:request_from_lsp("textDocument/codeAction", arg)
    if req.kind ~= "ReqCodeAction" then error("code_action: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc or not self._codeaction_engine then return C.LspCodeActionList({}) end

    local report = self:diagnostic(C.ReqDiagnostic(C.LspDocIdentifier(doc.uri)))
    local q = C.CodeActionQuery(doc.file, doc.uri, req.range, report.items or {})
    return self._codeaction_engine.plan_code_actions(q)
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

    local spans = self._semtokens_engine.plan_semantic_tokens(
        C.LspSemanticTokenQuery(doc.file, doc.uri, doc.text or "")
    ).items

    return encode_semantic_tokens(C, spans)
end

function Core:semantic_tokens_range(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSemanticTokensRange") and arg or self:request_from_lsp("textDocument/semanticTokens/range", arg)
    if req.kind ~= "ReqSemanticTokensRange" then error("semantic_tokens_range: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc or not self._semtokens_engine then return C.LspSemanticTokens({}) end

    local src = self._semtokens_engine.plan_semantic_tokens(
        C.LspSemanticTokenQuery(doc.file, doc.uri, doc.text or "")
    ).items

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

    local out, seen = {}, {}
    local function add_hint_for_anchor(anchor, tstr)
        if not anchor or not tstr or tstr == "" or tstr == "any" or tstr == "unknown" then return end
        local r = self:_range_for(doc.file, anchor)
        local pos = C.LspPos(r.stop.line, r.stop.character)
        if not position_in_range(pos, req.range) then return end
        local key = pos.line .. ":" .. pos.character .. ":" .. tstr
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspInlayHint(pos, ": " .. tstr, C.InlayType)
    end

    if self._type_engine then
        local ti = self._type_engine.typed_index(doc.file)
        for i = 1, #ti.symbols do
            local ts = ti.symbols[i]
            local sym = ts.symbol
            if sym and sym.decl_anchor and (sym.kind == C.SymLocal or sym.kind == C.SymParam) then
                add_hint_for_anchor(sym.decl_anchor, self._type_engine.type_to_string(ts.typ))
            end
        end
    end

    local function expr_type_name(e)
        if not e then return nil end
        if e.kind == "Number" then return "number" end
        if e.kind == "String" then return "string" end
        if e.kind == "True" or e.kind == "False" then return "boolean" end
        if e.kind == "Nil" then return "nil" end
        if e.kind == "TableCtor" then return "table" end
        if e.kind == "FunctionExpr" then return "fun" end
        return nil
    end

    for i = 1, #doc.file.items do
        local item = doc.file.items[i]
        local s = item.stmt
        if s.kind == "LocalAssign" then
            for j = 1, #s.names do
                local tname = expr_type_name(s.values[j])
                add_hint_for_anchor(C.AnchorRef(tostring(s.names[j])), tname)
            end
        elseif s.kind == "LocalFunction" then
            add_hint_for_anchor(C.AnchorRef(tostring(s)), "fun")
        end
    end

    table.sort(out, function(a, b)
        if a.position.line ~= b.position.line then return a.position.line < b.position.line end
        return a.position.character < b.position.character
    end)

    return C.LspInlayHintList(out)
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
        fr = self._format_engine.format_file(C.FormatQuery(doc.file, opts, req.range, req.has_range))
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

    local lines, n = split_lines(doc.text or "")
    local out, seen = {}, {}

    local function add_fold(line0s, line0e, kind, scol, ecol)
        if not line0s or not line0e or line0e <= line0s then return end
        local end_line_text = lines[line0e + 1] or ""
        local ec = ecol or byte_to_utf16_col_in_line(end_line_text, #end_line_text + 1)
        local key = line0s .. ":" .. line0e .. ":" .. (kind and tostring(kind) or "")
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspFoldingRange(line0s, scol or 0, line0e, ec, kind or C.FoldRegion)
    end

    -- AST-aware region folds
    for i = 1, #doc.file.items do
        local s = doc.file.items[i].stmt
        local k = s and s.kind or ""
        if k == "If" or k == "While" or k == "Repeat" or k == "ForNum" or k == "ForIn"
            or k == "Do" or k == "Function" or k == "LocalFunction" then
            local r = self:_range_for(doc.file, C.AnchorRef(tostring(s)))
            if r and r.start and r.stop then
                add_fold(r.start.line, r.stop.line, C.FoldRegion, r.start.character, r.stop.character)
            end
        end
    end

    -- Comment-block folds
    local comment_start = nil
    for i = 1, n do
        local s = (lines[i] or ""):match("^%s*(.-)%s*$")
        if s:match("^%-%-") then
            if not comment_start then comment_start = i end
        else
            if comment_start and (i - comment_start) >= 2 then
                add_fold(comment_start - 1, i - 2, C.FoldComment, 0, nil)
            end
            comment_start = nil
        end
    end
    if comment_start and (n - comment_start + 1) >= 2 then
        add_fold(comment_start - 1, n - 1, C.FoldComment, 0, nil)
    end

    table.sort(out, function(a, b)
        if a.start_line ~= b.start_line then return a.start_line < b.start_line end
        if a.end_line ~= b.end_line then return a.end_line < b.end_line end
        return a.start_character < b.start_character
    end)

    return C.LspFoldingRangeList(out)
end

function Core:selection_range(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqSelectionRange") and arg or self:request_from_lsp("textDocument/selectionRange", arg)
    if req.kind ~= "ReqSelectionRange" then error("selection_range: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspSelectionRangeList({}) end

    local entries = self.adapter:all_anchor_entries(doc.file).items or {}
    local out = {}

    for i = 1, #req.positions do
        local p = req.positions[i]
        local pos = C.LspPos(p.line, p.character)

        local hits = {}
        for j = 1, #entries do
            local e = entries[j]
            if position_in_range(pos, e.range) then hits[#hits + 1] = e.range end
        end
        table.sort(hits, function(a, b) return range_size_key(a) < range_size_key(b) end)

        if #hits > 0 then
            local primary = hits[1]
            local parents = {}
            for j = 2, #hits do parents[#parents + 1] = hits[j] end
            out[#out + 1] = C.LspSelectionRange(primary, parents)
        else
            local line_start, line_end = line_bounds(doc.text or "", p.line)
            local line_text = (doc.text or ""):sub(line_start, line_end - 1)
            local bi = utf16_col_to_byte_in_line(line_text, p.character)
            if bi < 1 then bi = 1 end
            if bi > #line_text then bi = #line_text end

            local l, r = bi, bi
            local function ident(ch) return ch and ch:match("[%w_]") ~= nil end
            if #line_text > 0 and not ident(line_text:sub(bi, bi)) and bi > 1 and ident(line_text:sub(bi - 1, bi - 1)) then
                l, r = bi - 1, bi - 1
            end
            if #line_text > 0 and ident(line_text:sub(l, l)) then
                while l > 1 and ident(line_text:sub(l - 1, l - 1)) do l = l - 1 end
                while r < #line_text and ident(line_text:sub(r + 1, r + 1)) do r = r + 1 end
            end

            local sc = byte_to_utf16_col_in_line(line_text, l)
            local ec = byte_to_utf16_col_in_line(line_text, r + 1)
            if ec < sc then ec = sc end
            local rr = C.LspRange(C.LspPos(p.line, sc), C.LspPos(p.line, ec))
            local line_rr = C.LspRange(C.LspPos(p.line, 0), C.LspPos(p.line, byte_to_utf16_col_in_line(line_text, #line_text + 1)))
            out[#out + 1] = C.LspSelectionRange(rr, { line_rr })
        end
    end

    return C.LspSelectionRangeList(out)
end

function Core:code_lens(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqCodeLens") and arg or self:request_from_lsp("textDocument/codeLens", arg)
    if req.kind ~= "ReqCodeLens" then error("code_lens: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspCodeLensList({}) end

    local out = {}
    for i = 1, #doc.file.items do
        local s = doc.file.items[i].stmt
        if s and (s.kind == "Function" or s.kind == "LocalFunction") then
            local r = self:_range_for(doc.file, C.AnchorRef(tostring(s)))
            out[#out + 1] = C.LspCodeLens(
                C.LspRange(C.LspPos(r.start.line, 0), C.LspPos(r.start.line, 1)),
                "Run solve",
                "lua.solve"
            )
        end
    end
    return C.LspCodeLensList(out)
end

function Core:document_color(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqDocumentColor") and arg or self:request_from_lsp("textDocument/documentColor", arg)
    if req.kind ~= "ReqDocumentColor" then error("document_color: invalid request", 2) end

    local doc = self:_doc(req.doc.uri)
    if not doc then return C.LspColorInfoList({}) end

    local out = {}
    local seen = {}
    local text = doc.text or ""

    local function add_color(line0, startc, endc, r, g, b, a)
        local key = line0 .. ":" .. startc .. ":" .. endc
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspColorInfo(
            C.LspRange(C.LspPos(line0, startc), C.LspPos(line0, endc)),
            C.LspColor(r / 255, g / 255, b / 255, a / 255)
        )
    end

    if self._lexer_engine and self._lexer_engine.lex_with_positions then
        local src = C.SourceFile(req.doc.uri, text)
        local lexed = self._lexer_engine.lex_with_positions(src)
        local tokens = lexed.tokens or {}
        local positions = lexed.positions or {}
        local count = lexed.count or #tokens

        for i = 1, count do
            local tok = tokens[i]
            local pos = positions[i]
            if tok and pos and tok.kind == "<number>" then
                local v = tostring(tok.value or ""):gsub("_", "")
                v = v:gsub("[uUlLiI]+$", "")
                local rr, gg, bb, aa = v:match("^0[xX](%x%x)(%x%x)(%x%x)(%x%x)$")
                if rr and gg and bb and aa then
                    local line0 = (pos.line or 1) - 1
                    local line_start = line_bounds(text, line0)
                    local start_off = pos.offset or line_start
                    local stop_off = pos.end_offset or start_off
                    if stop_off < start_off then stop_off = start_off end
                    local prefix = text:sub(line_start, math.max(line_start, start_off) - 1)
                    local token_txt = text:sub(start_off, stop_off)
                    local startc = utf16_len(prefix)
                    local endc = startc + utf16_len(token_txt)
                    add_color(line0, startc, endc,
                        tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16), tonumber(aa, 16))
                end
            end
        end
    end

    return C.LspColorInfoList(out)
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

    local q = (req.query or ""):lower()
    local out = {}
    local docs = self.docs.docs

    local function add(name, kind, uri, range, container)
        if not name or name == "" then return end
        if q ~= "" and not name:lower():find(q, 1, true) then return end
        out[#out + 1] = C.LspWorkspaceSymbol(name, kind or 13, uri or "", range, container or "")
    end

    for i = 1, #docs do
        local d = docs[i]
        local idx = self.engine:index(d.file)
        for j = 1, #idx.defs do
            local occ = idx.defs[j]
            add(occ.name, ws_symbol_kind(occ.kind), d.uri, self:_range_for(d.file, occ.anchor), "")
        end

        local env = self.engine.resolve_named_types(d.file)
        for j = 1, #env.classes do
            local cls = env.classes[j]
            add(cls.name, 5, d.uri, self:_range_for(d.file, cls.anchor), "")
            for k = 1, #cls.fields do
                local f = cls.fields[k]
                add(f.name, 8, d.uri, self:_range_for(d.file, f.anchor), cls.name)
            end
        end
        for j = 1, #env.aliases do
            local a = env.aliases[j]
            add(a.name, 13, d.uri, self:_range_for(d.file, a.anchor), "")
        end
        for j = 1, #env.generics do
            local g = env.generics[j]
            add(g.name, 26, d.uri, self:_range_for(d.file, g.anchor), "")
        end
    end

    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.uri ~= b.uri then return a.uri < b.uri end
        if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
        return a.range.start.character < b.range.start.character
    end)

    return C.LspWorkspaceSymbolList(out)
end

function Core:workspace_diagnostic(arg)
    local C = self.engine.C
    local tag = tostring(arg):match("^Lua%.([%w_]+)%(")
    local req = (tag == "ReqWorkspaceDiagnostic") and arg or self:request_from_lsp("workspace/diagnostic", arg)
    if req.kind ~= "ReqWorkspaceDiagnostic" then error("workspace_diagnostic: invalid request", 2) end

    local out = {}
    local docs = self.docs.docs
    for i = 1, #docs do
        local d = docs[i]
        local rep = self:diagnostic(C.ReqDiagnostic(C.LspDocIdentifier(d.uri)))
        local wk = C.WsDiagFull
        if rep.kind == C.DiagReportUnchanged then wk = C.WsDiagUnchanged end
        out[#out + 1] = C.LspWorkspaceDiagnosticItem(d.uri, d.version or 0, wk, rep.items or {})
    end
    return C.LspWorkspaceDiagnostic(out)
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
