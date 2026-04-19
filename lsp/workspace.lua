-- lsp/workspace.lua
--
-- Workspace-scoped semantic queries and protocol products.
--
-- Cached boundaries live over ParsedDocStore plus explicit extra args:
--   store + name/query/include_decl -> locations / symbols / diagnostics

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

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
    p = p:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
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
    add(noext:match("([^/]+)$"))

    local cwd = os.getenv("PWD") or ""
    if cwd ~= "" and noext:sub(1, #cwd) == cwd then
        add(noext:sub(#cwd + 2))
    end

    if noext:match("/init$") then
        local parent = noext:gsub("/init$", "")
        add(parent:match("([^/]+)$"))
        if cwd ~= "" and parent:sub(1, #cwd) == cwd then
            add(parent:sub(#cwd + 2))
        end
    end

    return names
end

local function require_alias_map(text)
    local out = {}
    for alias, mod in (text or ""):gmatch("local%s+([%a_][%w_]*)%s*=%s*require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
        out[alias] = normalize_module_name(mod)
    end
    return out
end

local function line_bounds(text, line0)
    local line = line0 or 0
    if line < 0 then line = 0 end
    local pos, cur = 1, 0
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

local function ws_symbol_kind(C, sk)
    local k = tostring(sk):match("^Lua%.([%w_]+)") or ""
    if k == "SymBuiltin" then return 12 end
    if k == "SymTypeClass" then return 5 end
    if k == "SymTypeGeneric" then return 26 end
    return 13
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

function M.new(semantics_engine, type_engine, opts)
    opts = opts or {}
    local C = semantics_engine.C
    local self = {}

    local function range_for(doc, anchor)
        if opts.range_for then return opts.range_for(doc, anchor) end
        return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
    end

    local function add_loc(out, seen, uri, file, anchor)
        if not uri or not file or not anchor then return end
        local r = range_for(file, anchor)
        local key = uri .. ":" .. r.start.line .. ":" .. r.start.character .. ":" .. r.stop.line .. ":" .. r.stop.character
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = C.LspLocation(uri, r)
    end

    local function workspace_type_target(store, name)
        local docs = store.docs
        for i = 1, #docs do
            local tt = pvm.one(semantics_engine:type_target(docs[i], name))
            if tt and tt.kind ~= "TypeTargetMissing" then return tt end
        end
        return nil
    end

    local function expand_type_names(store, seed)
        local out, seen, q = {}, {}, {}
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
            local tt = workspace_type_target(store, n)
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

    local function class_field_type_names(store, class_name, field_name)
        local out, seen = {}, {}
        local docs = store.docs

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
                local env = semantics_engine:type_env(d)
                for j = 1, #env.classes do
                    local cls = env.classes[j]
                    if cls.name == cname then
                        for k = 1, #cls.fields do
                            local f = cls.fields[k]
                            if f.name == field_name then collect_named_from_typeexpr(f.typ, out, seen) end
                        end
                        for k = 1, #cls.extends do
                            local ex = cls.extends[k]
                            if ex and ex.kind == "TNamed" and ex.name then gather_for_class(ex.name, visited) end
                        end
                    end
                end

                for j = 1, #d.items do
                    local item = d.items[j].core
                    local s = item.stmt
                    if s and s.kind == "Function" and s.name and (s.name.kind == "LMethod" or s.name.kind == "LField") then
                        local base_name = expr_terminal_name(s.name.base)
                        local member = (s.name.kind == "LMethod") and s.name.method or s.name.key
                        if base_name == cname and member == field_name then collect_return_names_from_item(item) end
                    end
                end
            end
        end

        gather_for_class(class_name, {})
        return out
    end

    local module_locations = pvm.phase("workspace_module_locations", function(store, module_name)
        local mod = normalize_module_name(module_name)
        if not mod or mod == "" then return C.LspLocationList({}) end
        local out = {}
        local docs = store.docs
        for i = 1, #docs do
            local names = module_names_for_uri(docs[i].uri)
            for j = 1, #names do
                if names[j] == mod then
                    out[#out + 1] = C.LspLocation(docs[i].uri, C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)))
                    break
                end
            end
        end
        return C.LspLocationList(out)
    end)

    local global_locations = pvm.phase("workspace_global_locations", function(store, name, include_declaration)
        local out, seen = {}, {}
        local docs = store.docs
        for i = 1, #docs do
            local d = docs[i]
            local idx = semantics_engine:index(d)
            if include_declaration then
                for j = 1, #idx.defs do
                    local occ = idx.defs[j]
                    if occ.name == name and occ.kind == C.SymGlobal then add_loc(out, seen, d.uri, d, occ.anchor) end
                end
            end
            for j = 1, #idx.uses do
                local occ = idx.uses[j]
                if occ.name == name and occ.kind == C.SymGlobal then add_loc(out, seen, d.uri, d, occ.anchor) end
            end
            for j = 1, #idx.unresolved do
                local occ = idx.unresolved[j]
                if occ.name == name then add_loc(out, seen, d.uri, d, occ.anchor) end
            end
        end
        return C.LspLocationList(out)
    end)

    local type_locations = pvm.phase("workspace_type_locations", function(store, name)
        local out, seen = {}, {}
        local docs = store.docs
        for i = 1, #docs do
            local d = docs[i]
            local tt = pvm.one(semantics_engine:type_target(d, name))
            if tt and tt.kind ~= "TypeTargetMissing" and tt.anchor then add_loc(out, seen, d.uri, d, tt.anchor) end
        end
        return C.LspLocationList(out)
    end)

    local type_implementations = pvm.phase("workspace_type_implementations", function(store, name)
        local out, seen = {}, {}
        local docs = store.docs
        for i = 1, #docs do
            local d = docs[i]
            local env = semantics_engine:type_env(d)
            for j = 1, #env.classes do
                local cls = env.classes[j]
                for k = 1, #cls.extends do
                    local ex = cls.extends[k]
                    if type(ex) == "table" and ex.kind == "TNamed" and ex.name == name then
                        add_loc(out, seen, d.uri, d, cls.anchor)
                        break
                    end
                end
            end
        end
        return C.LspLocationList(out)
    end)

    local module_field_locations = pvm.phase("workspace_module_field_locations", function(store, module_name, field, include_declaration)
        local mod = normalize_module_name(module_name)
        local fname = tostring(field or "")
        if mod == nil or mod == "" or fname == "" then return C.LspLocationList({}) end

        local out, seen = {}, {}

        local function add(uri, line, scol, ecol)
            local key = uri .. ":" .. line .. ":" .. scol .. ":" .. ecol
            if seen[key] then return end
            seen[key] = true
            out[#out + 1] = C.LspLocation(uri, C.LspRange(C.LspPos(line, scol), C.LspPos(line, ecol)))
        end

        local module_docs = {}
        for i = 1, #store.docs do
            local d = store.docs[i]
            local names = module_names_for_uri(d.uri)
            for j = 1, #names do if names[j] == mod then module_docs[#module_docs + 1] = d; break end end
        end

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

        for i = 1, #store.docs do
            local d = store.docs[i]
            local aliases = require_alias_map(d.text or "")
            local alias_list = {}
            for a, m in pairs(aliases) do if m == mod then alias_list[#alias_list + 1] = a end end
            if #alias_list > 0 then
                local line_no = 0
                for line in ((d.text or "") .. "\n"):gmatch("([^\n]*)\n") do
                    for j = 1, #alias_list do
                        local a = alias_list[j]
                        local s = line:find(a .. "%s*[%.:]%s*" .. fname)
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
    end)

    local workspace_symbols = pvm.phase("workspace_symbols", function(q)
        local query = (q.query or ""):lower()
        local out = {}

        local function add(name, kind, uri, range, container)
            if not name or name == "" then return end
            if query ~= "" and not name:lower():find(query, 1, true) then return end
            out[#out + 1] = C.LspWorkspaceSymbol(name, kind or 13, uri or "", range, container or "")
        end

        local docs = q.store.docs
        for i = 1, #docs do
            local d = docs[i]
            local idx = semantics_engine:index(d)
            for j = 1, #idx.defs do
                local occ = idx.defs[j]
                add(occ.name, ws_symbol_kind(C, occ.kind), d.uri, range_for(d, occ.anchor), "")
            end

            local env = semantics_engine:type_env(d)
            for j = 1, #env.classes do
                local cls = env.classes[j]
                add(cls.name, 5, d.uri, range_for(d, cls.anchor), "")
                for k = 1, #cls.fields do
                    local f = cls.fields[k]
                    add(f.name, 8, d.uri, range_for(d, f.anchor), cls.name)
                end
            end
            for j = 1, #env.aliases do
                local a = env.aliases[j]
                add(a.name, 13, d.uri, range_for(d, a.anchor), "")
            end
            for j = 1, #env.generics do
                local g = env.generics[j]
                add(g.name, 26, d.uri, range_for(d, g.anchor), "")
            end
        end

        table.sort(out, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            if a.uri ~= b.uri then return a.uri < b.uri end
            if a.range.start.line ~= b.range.start.line then return a.range.start.line < b.range.start.line end
            return a.range.start.character < b.range.start.character
        end)

        return C.LspWorkspaceSymbolList(out)
    end)

    local workspace_diagnostics = pvm.phase("workspace_diagnostics", function(q)
        local out = {}
        local docs = q.store.docs
        for i = 1, #docs do
            local d = docs[i]
            local rep = opts.lsp_diagnostic_report and opts.lsp_diagnostic_report(d) or nil
            local kind = C.WsDiagFull
            local items = {}
            if rep then
                local kk = tostring(rep.kind):match("^Lua%.([%w_]+)") or ""
                if kk == "DiagReportUnchanged" then kind = C.WsDiagUnchanged end
                items = rep.items or {}
            end
            out[#out + 1] = C.LspWorkspaceDiagnosticItem(d.uri, d.version or 0, kind, items)
        end
        return C.LspWorkspaceDiagnostic(out)
    end)

    self.module_locations_phase = module_locations
    self.global_locations_phase = global_locations
    self.type_locations_phase = type_locations
    self.type_implementations_phase = type_implementations
    self.module_field_locations_phase = module_field_locations
    self.workspace_symbols_phase = workspace_symbols
    self.workspace_diagnostics_phase = workspace_diagnostics

    function self:named_type_names(t)
        local out = {}
        collect_named_from_typeexpr(t, out, {})
        return out
    end
    function self:workspace_type_target(store, name) return workspace_type_target(store, name) end
    function self:expand_type_names(store, seed) return expand_type_names(store, seed) end
    function self:class_field_type_names(store, class_name, field_name) return class_field_type_names(store, class_name, field_name) end
    function self:module_locations(store, module_name) return pvm.one(module_locations(store, module_name)) end
    function self:global_locations(store, name, include_declaration) return pvm.one(global_locations(store, name, include_declaration and true or false)) end
    function self:type_locations(store, name) return pvm.one(type_locations(store, name)) end
    function self:type_implementations(store, name) return pvm.one(type_implementations(store, name)) end
    function self:module_field_locations(store, module_name, field, include_declaration) return pvm.one(module_field_locations(store, module_name, field, include_declaration and true or false)) end
    function self:workspace_symbols(store, query) return pvm.one(workspace_symbols(C.WorkspaceSymbolQuery(store, query or ""))) end
    function self:workspace_diagnostics(store) return pvm.one(workspace_diagnostics(C.WorkspaceDiagnosticQuery(store))) end

    return self
end

return M
