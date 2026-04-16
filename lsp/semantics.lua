-- lsp/semantics.lua
--
-- Semantic boundaries over the Lua AST (ASDL layer).
--
-- Cached phases (persistent semantic units):
--   collect_doc_types  — Item/ParsedDoc → DocEvent*
--   scope_events       — legacy low-level AST walk, not the semantic center
--   item_scope_events  — Item → ScopeEvent*
--   item_type_env      — Item → ItemTypeEnv
--   item_symbol_index  — Item → ItemSymbolIndex
--   item_scope_summary — Item → ItemScopeSummary
--   item_semantics     — Item → ItemSemantics
--   item_unknown_type_diagnostics — (Item, KnownTypeSet) → Diagnostic*
--
-- Assembly helpers (not cached at whole-file identity):
--   resolve_named_types — ParsedDoc → TypeEnv
--   symbol_index        — ParsedDoc → SymbolIndex
--   scope_diagnostics   — ParsedDoc → Diagnostic*
--   diagnostics         — ParsedDoc → Diagnostic*
--
-- Query phases:
--   symbol_for_anchor   — SubjectQuery → AnchorBinding
--   type_target         — TypeNameQuery → TypeTarget
--   goto_definition     — SubjectQuery → DefinitionResult
--   hover               — SubjectQuery → HoverInfo
--   definitions_of      — SymbolIdQuery → Occurrence*
--   references_of       — SymbolIdQuery → Occurrence*
--   find_references     — RefQuery → Occurrence*

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")

local M = {}

-- ── Built-in tables ────────────────────────────────────────

local BUILTIN_GLOBALS = {
    _G = true, _VERSION = true,
    assert = true, collectgarbage = true, dofile = true, error = true,
    getmetatable = true, ipairs = true, load = true, loadfile = true,
    next = true, pairs = true, pcall = true, print = true, rawequal = true,
    rawget = true, rawlen = true, rawset = true, require = true,
    select = true, setmetatable = true, tonumber = true, tostring = true,
    type = true, xpcall = true, unpack = true,
    math = true, string = true, table = true, coroutine = true,
    io = true, os = true, debug = true, package = true, utf8 = true,
    arg = true, bit = true, ffi = true, jit = true,  -- LuaJIT

    -- Common host/test globals (pragmatic defaults)
    vim = true, love = true,
    describe = true, it = true, before_each = true, after_each = true,
    before_all = true, after_all = true, pending = true,
}

local EXTRA_GLOBALS = os.getenv("PVM_LSP_GLOBALS")
if EXTRA_GLOBALS and EXTRA_GLOBALS ~= "" then
    for g in EXTRA_GLOBALS:gmatch("[^,%s]+") do
        BUILTIN_GLOBALS[g] = true
    end
end

local BUILTIN_TYPES = {
    any = true, unknown = true,
    ["nil"] = true, boolean = true, number = true, string = true,
    table = true, ["function"] = true, thread = true, userdata = true,
}

-- ── Helpers ────────────────────────────────────────────────

local function append_trip(trips, g, p, c)
    trips[#trips + 1] = { g, p, c }
end

local function anchor_ref(C, v)
    if not v then return nil end
    if type(v) == "table" then
        local tv = tostring(v)
        if tv:match("^Lua%.AnchorRef%(") then return v end
    end
    return C.AnchorRef(tostring(v))
end

local function doc_items(doc)
    return (doc and doc.items) or {}
end

local function syntax_item(v)
    return v and v.syntax or nil
end

local function semantic_part(v)
    return v and v.semantics or nil
end

local function contains_name(names, name)
    for i = 1, #names do
        if names[i] == name then return true end
    end
    return false
end

local function add_name_unique(names, name)
    if not contains_name(names, name) then
        names[#names + 1] = name
    end
end

local function add_named_type_refs(typ, out)
    if typ == nil then return end
    local k = typ.kind

    if k == "TNamed" then
        add_name_unique(out, typ.name); return
    end
    if k == "TUnion" or k == "TIntersect" then
        for i = 1, #typ.parts do add_named_type_refs(typ.parts[i], out) end; return
    end
    if k == "TTuple" then
        for i = 1, #typ.items do add_named_type_refs(typ.items[i], out) end; return
    end
    if k == "TArray" or k == "TOptional" or k == "TVararg" or k == "TParen" then
        add_named_type_refs(typ.inner or typ.item, out); return
    end
    if k == "TMap" then
        add_named_type_refs(typ.key, out)
        add_named_type_refs(typ.value, out); return
    end
    if k == "TFunc" then
        local sig = typ.sig
        if sig then
            for i = 1, #sig.params do add_named_type_refs(sig.params[i], out) end
            for i = 1, #sig.returns do add_named_type_refs(sig.returns[i], out) end
        end; return
    end
    if k == "TTable" then
        for i = 1, #typ.fields do add_named_type_refs(typ.fields[i].typ, out) end; return
    end
end

-- ══════════════════════════════════════════════════════════════
--  Engine constructor
-- ══════════════════════════════════════════════════════════════

function M.new(ctx)
    ctx = ctx or ASDL.context()
    local C = ctx.Lua

    local function diag_code_name(c)
        local kk = tostring(c):match("^Lua%.([%w_]+)") or ""
        if kk == "DiagUndefinedGlobal" then return "undefined-global" end
        if kk == "DiagUnknownType" then return "unknown-type" end
        if kk == "DiagRedeclareLocal" then return "redeclare-local" end
        if kk == "DiagShadowingLocal" then return "shadowing-local" end
        if kk == "DiagShadowingGlobal" then return "shadowing-global" end
        if kk == "DiagUnusedParam" then return "unused-param" end
        return "unused-local"
    end

    local function scope_kind_name(s)
        local kk = tostring(s):match("^Lua%.([%w_]+)") or ""
        if kk == "ScopeFunction" then return "function" end
        if kk == "ScopeIf" then return "if" end
        if kk == "ScopeElse" then return "else" end
        if kk == "ScopeWhile" then return "while" end
        if kk == "ScopeRepeat" then return "repeat" end
        if kk == "ScopeFor" then return "for" end
        if kk == "ScopeDo" then return "do" end
        if kk == "ScopeType" then return "type" end
        return "file"
    end

    local function symbol_kind_from_decl(dk)
        if dk == C.DeclParam then return C.SymParam end
        return C.SymLocal
    end

    local function type_target_symbol_kind(tt)
        if tt.kind == "TypeClassTarget" then return C.SymTypeClass end
        if tt.kind == "TypeAliasTarget" then return C.SymTypeAlias end
        if tt.kind == "TypeGenericTarget" then return C.SymTypeGeneric end
        if tt.kind == "TypeBuiltinTarget" then return C.SymTypeBuiltin end
        return C.SymTypeBuiltin
    end

    -- ── collect_doc_types phase ────────────────────────────
    local collect_doc_types
    local item_scope_summary
    local item_semantics
    local semantic_doc
    collect_doc_types = pvm.phase("collect_doc_types", {
        [C.ParsedDoc] = function(n)
            local items = {}
            for i = 1, #n.items do items[i] = syntax_item(n.items[i]) end
            return pvm.children(collect_doc_types, items)
        end,
        [C.SemanticDoc] = function(n)
            local items = {}
            for i = 1, #n.items do items[i] = syntax_item(n.items[i]) end
            return pvm.children(collect_doc_types, items)
        end,
        [C.Item] = function(n)
            return pvm.children(collect_doc_types, n.docs)
        end,
        [C.DocBlock] = function(n)
            return pvm.children(collect_doc_types, n.tags)
        end,
        [C.ClassTag] = function(n)
            return pvm.once(C.DClass(n.name, n.extends, anchor_ref(C, n)))
        end,
        [C.FieldTag] = function(n)
            return pvm.once(C.DField(n.name, n.typ, n.optional, anchor_ref(C, n)))
        end,
        [C.AliasTag] = function(n)
            return pvm.once(C.DAlias(n.name, n.typ, anchor_ref(C, n)))
        end,
        [C.GenericTag] = function(n)
            return pvm.once(C.DGeneric(n.name, n.bounds, anchor_ref(C, n)))
        end,
        [C.TypeTag] = function(n)
            return pvm.once(C.DType(n.typ, anchor_ref(C, n)))
        end,
        [C.ParamTag] = function(n)
            return pvm.once(C.DParam(n.name, n.typ, anchor_ref(C, n)))
        end,
        [C.ReturnTag] = function(n)
            return pvm.once(C.DReturn(n.values, anchor_ref(C, n)))
        end,
        [C.OverloadTag] = function(n)
            return pvm.once(C.DOverload(n.sig, anchor_ref(C, n)))
        end,
        [C.CastTag] = function(n)
            return pvm.once(C.DCast(n.typ, anchor_ref(C, n)))
        end,
        [C.MetaTag] = function(n)
            return pvm.once(C.DMeta(n.name, n.text, anchor_ref(C, n)))
        end,
    })

    -- ── scope_events phase ─────────────────────────────────
    -- Walks the full AST emitting scope enter/exit + decl/ref/write events.
    -- This is the core semantic phase — all diagnostics and symbol indexing
    -- are derived from this event stream.

    local scope_events
    scope_events = pvm.phase("scope_events", {
        [C.ParsedDoc] = function(n)
            local items = {}
            for i = 1, #n.items do items[i] = syntax_item(n.items[i]) end
            local g1, p1, c1 = pvm.once(C.ScopeEnter(C.ScopeFile, anchor_ref(C, n)))
            local g2, p2, c2 = pvm.children(scope_events, items)
            local g3, p3, c3 = pvm.once(C.ScopeExit(C.ScopeFile, anchor_ref(C, n)))
            return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,
        [C.SemanticDoc] = function(n)
            local items = {}
            for i = 1, #n.items do items[i] = syntax_item(n.items[i]) end
            local g1, p1, c1 = pvm.once(C.ScopeEnter(C.ScopeFile, anchor_ref(C, n)))
            local g2, p2, c2 = pvm.children(scope_events, items)
            local g3, p3, c3 = pvm.once(C.ScopeExit(C.ScopeFile, anchor_ref(C, n)))
            return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,

        [C.Item] = function(n)
            return scope_events(n.stmt)
        end,

        [C.Block] = function(n)
            return pvm.children(scope_events, n.items)
        end,

        [C.FuncBody] = function(n)
            local trips = {}
            append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeFunction, anchor_ref(C, n))))
            for i = 1, #n.params do
                append_trip(trips, pvm.once(C.ScopeDeclLocal(C.DeclParam, n.params[i].name, anchor_ref(C, n.params[i]))))
            end
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit(C.ScopeFunction, anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.CondBlock] = function(n)
            local g1, p1, c1 = scope_events(n.cond)
            local g2, p2, c2 = scope_events(n.body)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.LocalAssign] = function(n)
            local trips = {}
            for i = 1, #n.values do append_trip(trips, scope_events(n.values[i])) end
            for i = 1, #n.names do
                append_trip(trips, pvm.once(C.ScopeDeclLocal(C.DeclLocal, n.names[i].value, anchor_ref(C, n.names[i]))))
            end
            return pvm.concat_all(trips)
        end,

        [C.Assign] = function(n)
            local trips = {}
            for i = 1, #n.rhs do append_trip(trips, scope_events(n.rhs[i])) end
            for i = 1, #n.lhs do
                local lv = n.lhs[i]
                if lv.kind == "LName" then
                    append_trip(trips, pvm.once(C.ScopeWrite(lv.name, anchor_ref(C, lv))))
                elseif lv.kind == "LField" then
                    append_trip(trips, scope_events(lv.base))
                elseif lv.kind == "LIndex" then
                    append_trip(trips, scope_events(lv.base))
                    append_trip(trips, scope_events(lv.key))
                elseif lv.kind == "LMethod" then
                    append_trip(trips, scope_events(lv.base))
                end
            end
            return pvm.concat_all(trips)
        end,

        [C.LocalFunction] = function(n)
            local g1, p1, c1 = pvm.once(C.ScopeDeclLocal(C.DeclLocal, n.name, anchor_ref(C, n)))
            local g2, p2, c2 = scope_events(n.body)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Function] = function(n)
            local trips = {}
            if n.name.kind == "LName" then
                append_trip(trips, pvm.once(C.ScopeWrite(n.name.name, anchor_ref(C, n.name))))
            elseif n.name.kind == "LField" then
                append_trip(trips, scope_events(n.name.base))
            elseif n.name.kind == "LIndex" then
                append_trip(trips, scope_events(n.name.base))
                append_trip(trips, scope_events(n.name.key))
            elseif n.name.kind == "LMethod" then
                append_trip(trips, scope_events(n.name.base))
            end
            append_trip(trips, scope_events(n.body))
            return pvm.concat_all(trips)
        end,

        [C.Return] = function(n)
            return pvm.children(scope_events, n.values)
        end,

        [C.CallStmt] = function(n)
            local g1, p1, c1 = scope_events(n.callee)
            local g2, p2, c2 = pvm.children(scope_events, n.args)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.If] = function(n)
            local trips = {}
            for i = 1, #n.arms do
                local arm = n.arms[i]
                append_trip(trips, scope_events(arm.cond))
                append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeIf, anchor_ref(C, arm))))
                append_trip(trips, scope_events(arm.body))
                append_trip(trips, pvm.once(C.ScopeExit(C.ScopeIf, anchor_ref(C, arm))))
            end
            if n.else_block then
                append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeElse, anchor_ref(C, n.else_block))))
                append_trip(trips, scope_events(n.else_block))
                append_trip(trips, pvm.once(C.ScopeExit(C.ScopeElse, anchor_ref(C, n.else_block))))
            end
            return pvm.concat_all(trips)
        end,

        [C.While] = function(n)
            local trips = {}
            append_trip(trips, scope_events(n.cond))
            append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeWhile, anchor_ref(C, n))))
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit(C.ScopeWhile, anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.Repeat] = function(n)
            local trips = {}
            append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeRepeat, anchor_ref(C, n))))
            append_trip(trips, scope_events(n.body))
            append_trip(trips, scope_events(n.cond))
            append_trip(trips, pvm.once(C.ScopeExit(C.ScopeRepeat, anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.ForNum] = function(n)
            local trips = {}
            append_trip(trips, scope_events(n.init))
            append_trip(trips, scope_events(n.limit))
            append_trip(trips, scope_events(n.step))
            append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeFor, anchor_ref(C, n))))
            append_trip(trips, pvm.once(C.ScopeDeclLocal(C.DeclLocal, n.name, anchor_ref(C, n))))
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit(C.ScopeFor, anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.ForIn] = function(n)
            local trips = {}
            for i = 1, #n.iter do append_trip(trips, scope_events(n.iter[i])) end
            append_trip(trips, pvm.once(C.ScopeEnter(C.ScopeFor, anchor_ref(C, n))))
            for i = 1, #n.names do
                append_trip(trips, pvm.once(C.ScopeDeclLocal(C.DeclLocal, n.names[i].value, anchor_ref(C, n.names[i]))))
            end
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit(C.ScopeFor, anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.Do] = function(n)
            local g1, p1, c1 = pvm.once(C.ScopeEnter(C.ScopeDo, anchor_ref(C, n)))
            local g2, p2, c2 = scope_events(n.body)
            local g3, p3, c3 = pvm.once(C.ScopeExit(C.ScopeDo, anchor_ref(C, n)))
            return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,

        [C.Break] = function() return pvm.empty() end,
        [C.Goto] = function() return pvm.empty() end,
        [C.Label] = function() return pvm.empty() end,

        -- Expressions
        [C.Nil]    = function() return pvm.empty() end,
        [C.True]   = function() return pvm.empty() end,
        [C.False]  = function() return pvm.empty() end,
        [C.Number] = function() return pvm.empty() end,
        [C.String] = function() return pvm.empty() end,
        [C.Vararg] = function() return pvm.empty() end,

        [C.NameRef] = function(n)
            return pvm.once(C.ScopeRef(n.name, anchor_ref(C, n)))
        end,

        [C.Field] = function(n)
            return scope_events(n.base)
        end,

        [C.Index] = function(n)
            local g1, p1, c1 = scope_events(n.base)
            local g2, p2, c2 = scope_events(n.key)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Call] = function(n)
            local g1, p1, c1 = scope_events(n.callee)
            local g2, p2, c2 = pvm.children(scope_events, n.args)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.MethodCall] = function(n)
            local g1, p1, c1 = scope_events(n.recv)
            local g2, p2, c2 = pvm.children(scope_events, n.args)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.FunctionExpr] = function(n)
            return scope_events(n.body)
        end,

        [C.TableCtor] = function(n)
            return pvm.children(scope_events, n.fields)
        end,

        [C.Unary] = function(n)
            return scope_events(n.value)
        end,

        [C.Binary] = function(n)
            local g1, p1, c1 = scope_events(n.lhs)
            local g2, p2, c2 = scope_events(n.rhs)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Paren] = function(n)
            return scope_events(n.inner)
        end,

        [C.ArrayField] = function(n)
            return scope_events(n.value)
        end,

        [C.PairField] = function(n)
            local g1, p1, c1 = scope_events(n.key)
            local g2, p2, c2 = scope_events(n.value)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.NameField] = function(n)
            return scope_events(n.value)
        end,
    })

    -- ── item_type_env phase ────────────────────────────────

    local item_type_env = pvm.phase("item_type_env", function(item)
        local classes, aliases, generics = {}, {}, {}
        local current_class = nil

        local function index_of(tbl, name)
            for i = 1, #tbl do if tbl[i].name == name then return i end end
            return nil
        end

        local function upsert_class(name, extends, anchor)
            local idx = index_of(classes, name)
            local fields = {}
            if idx then
                local old = classes[idx]
                for i = 1, #old.fields do fields[i] = old.fields[i] end
            end
            local cls = C.TypeClass(name, extends or {}, fields, anchor)
            if idx then classes[idx] = cls else classes[#classes + 1] = cls end
        end

        local function add_or_replace_field(cls, field)
            local fields, replaced = {}, false
            for i = 1, #cls.fields do
                if cls.fields[i].name == field.name then
                    fields[#fields + 1] = field; replaced = true
                else
                    fields[#fields + 1] = cls.fields[i]
                end
            end
            if not replaced then fields[#fields + 1] = field end
            return C.TypeClass(cls.name, cls.extends, fields, cls.anchor)
        end

        for _, e in collect_doc_types(item) do
            local k = e.kind
            if k == "DClass" then
                upsert_class(e.name, e.extends or {}, e.anchor)
                current_class = e.name
            elseif k == "DField" then
                if current_class then
                    local cidx = index_of(classes, current_class)
                    if cidx then
                        classes[cidx] = add_or_replace_field(classes[cidx],
                            C.TypeClassField(e.name, e.typ, e.optional, e.anchor))
                    end
                end
            elseif k == "DAlias" then
                local alias = C.TypeAlias(e.name, e.typ, e.anchor)
                local idx = index_of(aliases, e.name)
                if idx then aliases[idx] = alias else aliases[#aliases + 1] = alias end
                current_class = nil
            elseif k == "DGeneric" then
                local generic = C.TypeGeneric(e.name, e.bounds, e.anchor)
                local idx = index_of(generics, e.name)
                if idx then generics[idx] = generic else generics[#generics + 1] = generic end
            end
        end

        return C.ItemTypeEnv(classes, aliases, generics)
    end)

    -- ── resolve_named_types assembly ───────────────────────

    local function build_type_env_from_sem_items(items)
        local classes, aliases, generics = {}, {}, {}

        local function upsert_class(cls)
            local idx = nil
            for i = 1, #classes do if classes[i].name == cls.name then idx = i; break end end
            if not idx then
                classes[#classes + 1] = cls
                return
            end
            local old = classes[idx]
            local merged_fields = {}
            for i = 1, #old.fields do merged_fields[i] = old.fields[i] end
            for i = 1, #cls.fields do
                local field = cls.fields[i]
                local replaced = false
                for j = 1, #merged_fields do
                    if merged_fields[j].name == field.name then
                        merged_fields[j] = field
                        replaced = true
                        break
                    end
                end
                if not replaced then merged_fields[#merged_fields + 1] = field end
            end
            classes[idx] = C.TypeClass(cls.name, cls.extends, merged_fields, cls.anchor)
        end

        local function upsert_alias(alias)
            for i = 1, #aliases do
                if aliases[i].name == alias.name then aliases[i] = alias; return end
            end
            aliases[#aliases + 1] = alias
        end

        local function upsert_generic(generic)
            for i = 1, #generics do
                if generics[i].name == generic.name then generics[i] = generic; return end
            end
            generics[#generics + 1] = generic
        end

        for i = 1, #items do
            local part = semantic_part(items[i]).type_env
            for j = 1, #part.classes do upsert_class(part.classes[j]) end
            for j = 1, #part.aliases do upsert_alias(part.aliases[j]) end
            for j = 1, #part.generics do upsert_generic(part.generics[j]) end
        end

        return C.TypeEnv(classes, aliases, generics)
    end

    local function resolve_named_types(doc)
        return doc.type_env
    end

    -- ── item_unknown_type_diagnostics phase ───────────────

    local item_unknown_type_diagnostics = pvm.phase("item_unknown_type_diagnostics", {
        [C.Item] = function(item, known)
        local part = pvm.one(item_semantics(item)).type_env
        local out, n = {}, 0
        local seen = {}
        local names = (known and known.names) or {}

        local function emit_unknown(tname, owner, anchor)
            if contains_name(names, tname) or contains_name(seen, tname) then return end
            add_name_unique(seen, tname)
            n = n + 1
            out[n] = C.Diagnostic(C.DiagUnknownType,
                "unknown type '" .. tname .. "' in " .. owner, tname, C.ScopeType, anchor)
        end

        for i = 1, #part.classes do
            local cls = part.classes[i]
            for j = 1, #cls.extends do
                local refs = {}; add_named_type_refs(cls.extends[j], refs)
                for r = 1, #refs do emit_unknown(refs[r], "class " .. cls.name .. " extends", cls.anchor) end
            end
            for j = 1, #cls.fields do
                local f = cls.fields[j]
                local refs = {}; add_named_type_refs(f.typ, refs)
                for r = 1, #refs do emit_unknown(refs[r], "field " .. cls.name .. "." .. f.name, f.anchor) end
            end
        end
        for i = 1, #part.aliases do
            local a = part.aliases[i]
            local refs = {}; add_named_type_refs(a.typ, refs)
            for r = 1, #refs do emit_unknown(refs[r], "alias " .. a.name, a.anchor) end
        end

        return pvm.seq(out)
        end,
    })

    -- ── item_scope_events phase ────────────────────────────
    -- Converts the flat NameOcc array (extracted at parse time)
    -- into ScopeEvent nodes. No tree walking — just array iteration.
    -- Cached per Item identity.

    -- ── item_scope_events phase ────────────────────────────
    -- Extracts scope events from an Item by walking its Stmt tree.
    -- Pure Lua walk (no pvm phase overhead per AST node).
    -- Cached per Item identity.

    local item_scope_events = pvm.phase("item_scope_events", {
        [C.Item] = function(item)
        local out, n = {}, 0
        local function emit(ev) n = n + 1; out[n] = ev end

        local walk_expr, walk_stmt, walk_body, walk_block

        function walk_expr(e)
            if not e then return end
            local k = e.kind
            if k == "NameRef" then emit(C.ScopeRef(e.name, anchor_ref(C, e)))
            elseif k == "Field" then walk_expr(e.base)
            elseif k == "Index" then walk_expr(e.base); walk_expr(e.key)
            elseif k == "Call" then
                walk_expr(e.callee)
                for i = 1, #e.args do walk_expr(e.args[i]) end
            elseif k == "MethodCall" then
                walk_expr(e.recv)
                for i = 1, #e.args do walk_expr(e.args[i]) end
            elseif k == "FunctionExpr" then walk_body(e.body)
            elseif k == "TableCtor" then
                for i = 1, #e.fields do
                    local f = e.fields[i]
                    if f.kind == "ArrayField" then walk_expr(f.value)
                    elseif f.kind == "PairField" then walk_expr(f.key); walk_expr(f.value)
                    elseif f.kind == "NameField" then walk_expr(f.value) end
                end
            elseif k == "Unary" then walk_expr(e.value)
            elseif k == "Binary" then walk_expr(e.lhs); walk_expr(e.rhs)
            elseif k == "Paren" then walk_expr(e.inner)
            end
        end

        local function walk_lvalue(lv)
            if lv.kind == "LName" then emit(C.ScopeWrite(lv.name, anchor_ref(C, lv)))
            elseif lv.kind == "LField" then walk_expr(lv.base)
            elseif lv.kind == "LIndex" then walk_expr(lv.base); walk_expr(lv.key)
            elseif lv.kind == "LMethod" then walk_expr(lv.base) end
        end

        function walk_block(block)
            for i = 1, #block.items do walk_stmt(block.items[i].stmt) end
        end

        function walk_body(body, implicit_self)
            emit(C.ScopeEnter(C.ScopeFunction, anchor_ref(C, body)))
            if implicit_self then
                emit(C.ScopeDeclLocal(C.DeclParam, "self", anchor_ref(C, body)))
            end
            for i = 1, #body.params do
                emit(C.ScopeDeclLocal(C.DeclParam, body.params[i].name, anchor_ref(C, body.params[i])))
            end
            walk_block(body.body)
            emit(C.ScopeExit(C.ScopeFunction, anchor_ref(C, body)))
        end

        function walk_stmt(s)
            if not s then return end
            local k = s.kind
            if k == "LocalAssign" then
                for i = 1, #s.values do walk_expr(s.values[i]) end
                for i = 1, #s.names do emit(C.ScopeDeclLocal(C.DeclLocal, s.names[i].value, anchor_ref(C, s.names[i]))) end
            elseif k == "Assign" then
                for i = 1, #s.rhs do walk_expr(s.rhs[i]) end
                for i = 1, #s.lhs do walk_lvalue(s.lhs[i]) end
            elseif k == "LocalFunction" then
                emit(C.ScopeDeclLocal(C.DeclLocal, s.name, anchor_ref(C, s)))
                walk_body(s.body)
            elseif k == "Function" then
                local implicit_self = false
                if s.name.kind == "LName" then emit(C.ScopeWrite(s.name.name, anchor_ref(C, s.name)))
                elseif s.name.kind == "LField" then walk_expr(s.name.base)
                elseif s.name.kind == "LIndex" then walk_expr(s.name.base); walk_expr(s.name.key)
                elseif s.name.kind == "LMethod" then walk_expr(s.name.base); implicit_self = true end
                walk_body(s.body, implicit_self)
            elseif k == "Return" then
                for i = 1, #s.values do walk_expr(s.values[i]) end
            elseif k == "CallStmt" then
                walk_expr(s.callee)
                for i = 1, #s.args do walk_expr(s.args[i]) end
            elseif k == "If" then
                for i = 1, #s.arms do
                    walk_expr(s.arms[i].cond)
                    emit(C.ScopeEnter(C.ScopeIf, anchor_ref(C, s.arms[i])))
                    walk_block(s.arms[i].body)
                    emit(C.ScopeExit(C.ScopeIf, anchor_ref(C, s.arms[i])))
                end
                if s.else_block then
                    emit(C.ScopeEnter(C.ScopeElse, anchor_ref(C, s.else_block)))
                    walk_block(s.else_block)
                    emit(C.ScopeExit(C.ScopeElse, anchor_ref(C, s.else_block)))
                end
            elseif k == "While" then
                walk_expr(s.cond)
                emit(C.ScopeEnter(C.ScopeWhile, anchor_ref(C, s)))
                walk_block(s.body)
                emit(C.ScopeExit(C.ScopeWhile, anchor_ref(C, s)))
            elseif k == "Repeat" then
                emit(C.ScopeEnter(C.ScopeRepeat, anchor_ref(C, s)))
                walk_block(s.body)
                walk_expr(s.cond)
                emit(C.ScopeExit(C.ScopeRepeat, anchor_ref(C, s)))
            elseif k == "ForNum" then
                walk_expr(s.init); walk_expr(s.limit); walk_expr(s.step)
                emit(C.ScopeEnter(C.ScopeFor, anchor_ref(C, s)))
                emit(C.ScopeDeclLocal(C.DeclLocal, s.name, anchor_ref(C, s)))
                walk_block(s.body)
                emit(C.ScopeExit(C.ScopeFor, anchor_ref(C, s)))
            elseif k == "ForIn" then
                for i = 1, #s.iter do walk_expr(s.iter[i]) end
                emit(C.ScopeEnter(C.ScopeFor, anchor_ref(C, s)))
                for i = 1, #s.names do emit(C.ScopeDeclLocal(C.DeclLocal, s.names[i].value, anchor_ref(C, s.names[i]))) end
                walk_block(s.body)
                emit(C.ScopeExit(C.ScopeFor, anchor_ref(C, s)))
            elseif k == "Do" then
                emit(C.ScopeEnter(C.ScopeDo, anchor_ref(C, s)))
                walk_block(s.body)
                emit(C.ScopeExit(C.ScopeDo, anchor_ref(C, s)))
            end
        end

        walk_stmt(item.stmt)
        return pvm.seq(out)
        end,
    })

    -- ── file_scope_events phase ────────────────────────────
    -- Assembles per-item scope events into a file-level stream.
    -- Kept as a low-level fact view; not the semantic center.

    local file_scope_events = pvm.phase("file_scope_events", {
        [C.ParsedDoc] = function(file)
            local trips = {
                { pvm.once(C.ScopeEnter(C.ScopeFile, anchor_ref(C, file))) },
            }
            for i = 1, #file.items do
                trips[#trips + 1] = { item_scope_events(syntax_item(file.items[i])) }
            end
            trips[#trips + 1] = { pvm.once(C.ScopeExit(C.ScopeFile, anchor_ref(C, file))) }
            return pvm.concat_all(trips)
        end,
        [C.SemanticDoc] = function(file)
            local trips = {
                { pvm.once(C.ScopeEnter(C.ScopeFile, anchor_ref(C, file))) },
            }
            for i = 1, #file.items do
                trips[#trips + 1] = { item_scope_events(syntax_item(file.items[i])) }
            end
            trips[#trips + 1] = { pvm.once(C.ScopeExit(C.ScopeFile, anchor_ref(C, file))) }
            return pvm.concat_all(trips)
        end,
    })

    -- ── item_scope_summary phase ───────────────────────────

    item_scope_summary = pvm.phase("item_scope_summary", function(item)
        local events = pvm.drain(item_scope_events(item))
        local scopes = { { scope = C.ScopeFile, locals = {} } }
        local diagnostics, d_n = {}, 0
        local raw_ops, op_n = {}, 0

        local function add_diag(code, message, name, scope_kind, anchor)
            d_n = d_n + 1
            diagnostics[d_n] = C.Diagnostic(code, message, name or "", scope_kind or C.ScopeFile, anchor_ref(C, anchor or item))
        end

        local function current_scope() return scopes[#scopes] end

        local function find_local_in_frame(frame, name)
            for i = 1, #frame.locals do
                local info = frame.locals[i]
                if info.name == name then return info, i end
            end
            return nil, nil
        end

        local function find_local(name)
            for i = #scopes, 1, -1 do
                local hit = find_local_in_frame(scopes[i], name)
                if hit then return hit, i end
            end
            return nil, nil
        end

        local function push_scope(kind)
            scopes[#scopes + 1] = { scope = kind, locals = {} }
        end

        local function pop_scope()
            local scope = scopes[#scopes]
            if not scope then return end
            scopes[#scopes] = nil
            if scope.scope == C.ScopeFile then return end
            for i = 1, #scope.locals do
                local info = scope.locals[i]
                if info.used == 0 and info.name ~= "_" and info.name:sub(1, 1) ~= "_"
                    and not (info.decl_kind == C.DeclParam and info.name == "self") then
                    local code = (info.decl_kind == C.DeclParam) and C.DiagUnusedParam or C.DiagUnusedLocal
                    local cname = diag_code_name(code)
                    add_diag(code, cname:gsub("-", " ") .. " '" .. info.name .. "'",
                        info.name, scope.scope, info.anchor)
                end
            end
        end

        local function add_local(frame, info)
            frame.locals[#frame.locals + 1] = info
        end

        local function declare_local(name, decl_kind, anchor, scope_kind)
            local frame = current_scope()
            local hit = find_local_in_frame(frame, name)
            if hit then
                add_diag(C.DiagRedeclareLocal, "local '" .. name .. "' redeclared in same scope",
                    name, frame.scope, anchor)
                return
            end

            local outer_hit = false
            for i = #scopes - 1, 1, -1 do
                if find_local_in_frame(scopes[i], name) then outer_hit = true; break end
            end
            if outer_hit then
                add_diag(C.DiagShadowingLocal, "local '" .. name .. "' shadows outer local",
                    name, frame.scope, anchor)
            elseif BUILTIN_GLOBALS[name] then
                add_diag(C.DiagShadowingGlobal, "local '" .. name .. "' shadows global",
                    name, frame.scope, anchor)
            elseif frame.scope ~= C.ScopeFile then
                op_n = op_n + 1
                raw_ops[op_n] = { kind = "shadow", name = name, scope = frame.scope, anchor = anchor_ref(C, anchor) }
            end

            local info = {
                name = name,
                decl_kind = decl_kind or C.DeclLocal,
                used = 0,
                anchor = anchor_ref(C, anchor or item),
                scope = frame.scope,
            }
            add_local(frame, info)
            if frame.scope == C.ScopeFile then
                op_n = op_n + 1
                raw_ops[op_n] = { kind = "declare", info = info }
            end
        end

        local function mark_ref(name, anchor, is_write)
            local info = find_local(name)
            if info then
                info.used = info.used + 1
                return
            end
            op_n = op_n + 1
            raw_ops[op_n] = {
                kind = is_write and "write" or "read",
                name = name,
                scope = current_scope() and current_scope().scope or C.ScopeFile,
                anchor = anchor_ref(C, anchor or item),
            }
        end

        for i = 1, #events do
            local e = events[i]
            local ek = e.kind
            if     ek == "ScopeEnter"      then push_scope(e.scope)
            elseif ek == "ScopeExit"       then pop_scope()
            elseif ek == "ScopeDeclLocal"  then declare_local(e.name, e.decl_kind or C.DeclLocal, e.anchor, e.scope)
            elseif ek == "ScopeDeclGlobal" then
                op_n = op_n + 1
                raw_ops[op_n] = { kind = "write", name = e.name, scope = C.ScopeFile, anchor = anchor_ref(C, e.anchor) }
            elseif ek == "ScopeRef"        then mark_ref(e.name, e.anchor, false)
            elseif ek == "ScopeWrite"      then mark_ref(e.name, e.anchor, true)
            end
        end

        local ops = {}
        for i = 1, op_n do
            local op = raw_ops[i]
            if op.kind == "declare" then
                ops[i] = C.ItemScopeDeclareLocal(op.info.decl_kind, op.info.name, op.info.anchor, op.info.used)
            elseif op.kind == "shadow" then
                ops[i] = C.ItemScopeShadowCandidate(op.name, op.scope, op.anchor)
            elseif op.kind == "read" then
                ops[i] = C.ItemScopeOuterRead(op.name, op.scope, op.anchor)
            elseif op.kind == "write" then
                ops[i] = C.ItemScopeOuterWrite(op.name, op.scope, op.anchor)
            end
        end

        return C.ItemScopeSummary(ops, diagnostics)
    end)

    -- ── scope_diagnostics assembly ─────────────────────────

    local function build_scope_diagnostics_from_sem_items(items, doc_anchor)
        local out, n = {}, 0
        local file_locals = {}
        local global_declared = {}
        local seen_undef = {}

        local function add_diag(code, message, name, scope_kind, anchor)
            n = n + 1
            out[n] = C.Diagnostic(code, message, name or "", scope_kind or C.ScopeFile, anchor_ref(C, anchor or doc_anchor))
        end

        local function find_file_local(name)
            for i = 1, #file_locals do
                if file_locals[i].name == name then return file_locals[i] end
            end
            return nil
        end

        local function add_file_local(name, decl_kind, anchor, used_in_item)
            file_locals[#file_locals + 1] = {
                name = name,
                decl_kind = decl_kind,
                anchor = anchor,
                used = used_in_item or 0,
            }
        end

        local function mark_use(name)
            local info = find_file_local(name)
            if info then info.used = info.used + 1; return true end
            return false
        end

        for i = 1, #items do
            local summary = semantic_part(items[i]).scope_summary
            for j = 1, #summary.diagnostics do
                n = n + 1
                out[n] = summary.diagnostics[j]
            end
            for j = 1, #summary.ops do
                local op = summary.ops[j]
                local k = op.kind
                if k == "ItemScopeDeclareLocal" then
                    if find_file_local(op.name) then
                        add_diag(C.DiagRedeclareLocal, "local '" .. op.name .. "' redeclared in same scope",
                            op.name, C.ScopeFile, op.anchor)
                    else
                        if BUILTIN_GLOBALS[op.name] or contains_name(global_declared, op.name) then
                            add_diag(C.DiagShadowingGlobal, "local '" .. op.name .. "' shadows global",
                                op.name, C.ScopeFile, op.anchor)
                        end
                        add_file_local(op.name, op.decl_kind, op.anchor, op.used_in_item)
                    end
                elseif k == "ItemScopeShadowCandidate" then
                    if find_file_local(op.name) then
                        add_diag(C.DiagShadowingLocal, "local '" .. op.name .. "' shadows outer local",
                            op.name, op.scope, op.anchor)
                    elseif BUILTIN_GLOBALS[op.name] or contains_name(global_declared, op.name) then
                        add_diag(C.DiagShadowingGlobal, "local '" .. op.name .. "' shadows global",
                            op.name, op.scope, op.anchor)
                    end
                elseif k == "ItemScopeOuterRead" then
                    if not mark_use(op.name) and not BUILTIN_GLOBALS[op.name] and not contains_name(global_declared, op.name) then
                        if not contains_name(seen_undef, op.name) then
                            add_name_unique(seen_undef, op.name)
                            add_diag(C.DiagUndefinedGlobal, "undefined global '" .. op.name .. "'",
                                op.name, op.scope, op.anchor)
                        end
                    end
                elseif k == "ItemScopeOuterWrite" then
                    if not mark_use(op.name) then add_name_unique(global_declared, op.name) end
                end
            end
        end

        for i = 1, #file_locals do
            local info = file_locals[i]
            if info.used == 0 and info.name ~= "_" and info.name:sub(1, 1) ~= "_" then
                add_diag(C.DiagUnusedLocal, "unused local '" .. info.name .. "'",
                    info.name, C.ScopeFile, info.anchor)
            end
        end

        return out
    end

    local function scope_diagnostics(doc)
        return pvm.seq(build_scope_diagnostics_from_sem_items(doc.items, doc))
    end

    -- ── item_symbol_index phase ───────────────────────────

    local item_symbol_index = pvm.phase("item_symbol_index", function(item)
        local symbols, defs, uses, unresolved = {}, {}, {}, {}
        local scopes = {}
        local scope_seq = 0
        local globals = {}
        local item_anchor = anchor_ref(C, item)

        local function symbol_by_id(id)
            for i = 1, #symbols do if symbols[i].id == id then return symbols[i] end end
            return nil
        end

        local function add_symbol(id, kind, name, scope, scope_id, decl_anchor)
            local hit = symbol_by_id(id)
            if hit then return hit end
            local s = C.Symbol(id, kind, name, scope, scope_id, decl_anchor)
            symbols[#symbols + 1] = s
            return s
        end

        local function add_def(sym, anchor)
            defs[#defs + 1] = C.Occurrence(sym.id, sym.name, sym.kind, anchor_ref(C, anchor or item_anchor))
        end

        local function add_use(sym, anchor)
            uses[#uses + 1] = C.Occurrence(sym.id, sym.name, sym.kind, anchor_ref(C, anchor or item_anchor))
        end

        local function push_scope(kind, anchor)
            scope_seq = scope_seq + 1
            local id = tostring(item_anchor.id) .. ":" .. scope_kind_name(kind) .. ":" .. tostring(anchor or item_anchor) .. ":" .. tostring(scope_seq)
            scopes[#scopes + 1] = C.ScopeSymbolFrame(kind, id, {})
        end

        local function pop_scope() scopes[#scopes] = nil end
        local function current_scope() return scopes[#scopes] end

        local function find_local_in_frame(frame, name)
            for i = 1, #frame.locals do
                if frame.locals[i].name == name then return frame.locals[i].symbol end
            end
            return nil
        end

        local function find_local(name)
            for i = #scopes, 1, -1 do
                local hit = find_local_in_frame(scopes[i], name)
                if hit then return hit end
            end
            return nil
        end

        local function set_local(frame, name, sym)
            local locals, replaced = {}, false
            for i = 1, #frame.locals do
                if frame.locals[i].name == name then
                    locals[#locals + 1] = C.ScopeSymbolBinding(name, sym); replaced = true
                else
                    locals[#locals + 1] = frame.locals[i]
                end
            end
            if not replaced then locals[#locals + 1] = C.ScopeSymbolBinding(name, sym) end
            return C.ScopeSymbolFrame(frame.scope, frame.id, locals)
        end

        local function find_global(name)
            for i = 1, #globals do if globals[i].name == name then return globals[i] end end
            return nil
        end

        local function ensure_builtin(name)
            local hit = find_global(name)
            if hit then return hit end
            local sym = add_symbol("builtin:" .. name, C.SymBuiltin, name, C.ScopeFile, "file",
                anchor_ref(C, "builtin:" .. name))
            globals[#globals + 1] = sym
            return sym
        end

        local function ensure_global(name, anchor)
            local hit = find_global(name)
            if hit then return hit end
            local danchor = anchor_ref(C, anchor or ("global:" .. name))
            local sym = add_symbol("global:" .. name, C.SymGlobal, name, C.ScopeFile, "file", danchor)
            globals[#globals + 1] = sym
            add_def(sym, danchor)
            return sym
        end

        local function declare_local(name, decl_kind, anchor)
            local scope = current_scope()
            if not scope then return nil end
            local danchor = anchor_ref(C, anchor or (scope.id .. ":" .. name))
            local sk = symbol_kind_from_decl(decl_kind)
            local sym = add_symbol(danchor.id, sk, name, scope.scope, scope.id, danchor)
            scopes[#scopes] = set_local(scope, name, sym)
            add_def(sym, danchor)
            return sym
        end

        local function ref_name(name, anchor)
            local s = find_local(name)
            if s then add_use(s, anchor); return end
            s = find_global(name)
            if s then add_use(s, anchor); return end
            if BUILTIN_GLOBALS[name] then add_use(ensure_builtin(name), anchor); return end
            unresolved[#unresolved + 1] = C.Unresolved(name, anchor_ref(C, anchor or item_anchor))
        end

        local function write_name(name, anchor)
            local s = find_local(name)
            if s then add_use(s, anchor) else ensure_global(name, anchor) end
        end

        local function consume_event(e)
            local ek = e.kind
            if     ek == "ScopeEnter"      then push_scope(e.scope, e.anchor)
            elseif ek == "ScopeExit"       then pop_scope()
            elseif ek == "ScopeDeclLocal"  then declare_local(e.name, e.decl_kind or C.DeclLocal, e.anchor)
            elseif ek == "ScopeDeclGlobal" then ensure_global(e.name, e.anchor)
            elseif ek == "ScopeRef"        then ref_name(e.name, e.anchor)
            elseif ek == "ScopeWrite"      then write_name(e.name, e.anchor)
            end
        end

        consume_event(C.ScopeEnter(C.ScopeFile, item_anchor))
        for _, e in item_scope_events(item) do consume_event(e) end
        consume_event(C.ScopeExit(C.ScopeFile, item_anchor))

        return C.ItemSymbolIndex(symbols, defs, uses, unresolved)
    end)

    -- ── item_semantics phase ──────────────────────────────

    item_semantics = pvm.phase("item_semantics", function(item)
        return C.ItemSemantics(
            pvm.one(item_type_env(item)),
            pvm.one(item_symbol_index(item)),
            pvm.one(item_scope_summary(item))
        )
    end)

    -- ── symbol_index assembly ──────────────────────────────

    local function build_symbol_index_from_sem_items(items)
        local symbols, defs, uses, unresolved = {}, {}, {}, {}
        local top_locals = {}
        local globals_by_name = {}

        local function has_symbol(id)
            for i = 1, #symbols do if symbols[i].id == id then return true end end
            return false
        end

        local function add_symbol(sym)
            if not has_symbol(sym.id) then symbols[#symbols + 1] = sym end
            if sym.kind == C.SymGlobal or sym.kind == C.SymBuiltin then
                globals_by_name[sym.name] = sym
            end
        end

        local function symbol_by_id_local(part, id)
            for i = 1, #part.symbols do if part.symbols[i].id == id then return part.symbols[i] end end
            return nil
        end

        for i = 1, #items do
            local part = semantic_part(items[i]).symbol_index
            for j = 1, #part.symbols do add_symbol(part.symbols[j]) end
            for j = 1, #part.defs do defs[#defs + 1] = part.defs[j] end
            for j = 1, #part.uses do uses[#uses + 1] = part.uses[j] end
            for j = 1, #part.unresolved do
                local u = part.unresolved[j]
                local hit = top_locals[u.name] or globals_by_name[u.name]
                if hit then
                    uses[#uses + 1] = C.Occurrence(hit.id, hit.name, hit.kind, u.anchor)
                else
                    unresolved[#unresolved + 1] = u
                end
            end
            for j = 1, #part.defs do
                local occ = part.defs[j]
                local sym = symbol_by_id_local(part, occ.symbol_id)
                if sym and sym.scope == C.ScopeFile and sym.kind ~= C.SymGlobal and sym.kind ~= C.SymBuiltin then
                    top_locals[sym.name] = sym
                end
            end
        end

        return C.SymbolIndex(symbols, defs, uses, unresolved)
    end

    local function symbol_index(doc)
        return doc.symbol_index
    end

    -- ── diagnostics assembly ───────────────────────────────
    -- Combines scope diagnostics + unknown-type diagnostics from doc annotations.

    local function build_diagnostics_from_sem_items(items, env, doc_anchor)
        local out, n = {}, 0
        local function add(d) n = n + 1; out[n] = d end

        local sdiags = build_scope_diagnostics_from_sem_items(items, doc_anchor)
        for i = 1, #sdiags do add(sdiags[i]) end

        local known = {}
        for k in pairs(BUILTIN_TYPES) do add_name_unique(known, k) end
        for i = 1, #env.aliases  do add_name_unique(known, env.aliases[i].name) end
        for i = 1, #env.classes  do add_name_unique(known, env.classes[i].name) end
        for i = 1, #env.generics do add_name_unique(known, env.generics[i].name) end
        local known_set = C.KnownTypeSet(known)

        for i = 1, #items do
            local ds = pvm.drain(item_unknown_type_diagnostics(syntax_item(items[i]), known_set))
            for j = 1, #ds do add(ds[j]) end
        end

        return out
    end

    semantic_doc = pvm.phase("semantic_doc", function(parsed)
        local items = {}
        for i = 1, #parsed.items do
            local pit = parsed.items[i]
            items[i] = C.SemanticItem(pit.syntax, pit.span, pvm.one(item_semantics(pit.syntax)))
        end
        local env = build_type_env_from_sem_items(items)
        local idx = build_symbol_index_from_sem_items(items)
        local ds = build_diagnostics_from_sem_items(items, env, parsed)
        return C.SemanticDoc(parsed.uri, parsed.version, parsed.text, items, parsed.anchors, parsed.status, env, idx, ds)
    end)

    local function diagnostics(doc)
        return pvm.seq(doc.diagnostics)
    end

    -- ── Query lowers ───────────────────────────────────────

    local function symbol_by_id(idx, sid)
        for i = 1, #idx.symbols do if idx.symbols[i].id == sid then return idx.symbols[i] end end
        return nil
    end

    local function type_target_kind(tt)
        if tt.kind == "TypeClassTarget"   then return "class" end
        if tt.kind == "TypeAliasTarget"   then return "alias" end
        if tt.kind == "TypeGenericTarget" then return "generic" end
        if tt.kind == "TypeBuiltinTarget" then return "builtin-type" end
        return "unknown"
    end

    local function query_subject(v)
        if not v then return C.QueryMissing end
        if type(v) == "table" and v.kind == "TNamed" then return C.QueryTypeName(v.name) end
        if type(v) == "string" then return C.QueryTypeName(v) end
        return C.QueryAnchor(anchor_ref(C, v))
    end

    local definitions_of = pvm.phase("definitions_of", {
        [C.SymbolIdQuery] = function(q)
            local idx = symbol_index(q.doc)
            local out = {}
            for i = 1, #idx.defs do
                if idx.defs[i].symbol_id == q.symbol_id then out[#out + 1] = idx.defs[i] end
            end
            return pvm.seq(out)
        end,
    })

    local references_of = pvm.phase("references_of", {
        [C.SymbolIdQuery] = function(q)
            local idx = symbol_index(q.doc)
            local out = {}
            for i = 1, #idx.uses do
                if idx.uses[i].symbol_id == q.symbol_id then out[#out + 1] = idx.uses[i] end
            end
            return pvm.seq(out)
        end,
    })

    local symbol_for_anchor = pvm.phase("symbol_for_anchor", function(q)
        if not q.subject or q.subject.kind ~= "QueryAnchor" then return C.AnchorMissing end
        local target = q.subject.anchor
        local idx = symbol_index(q.doc)

        for i = 1, #idx.defs do
            if idx.defs[i].anchor == target then
                local sym = symbol_by_id(idx, idx.defs[i].symbol_id)
                if sym then return C.AnchorSymbol(sym, C.RoleDef) end
            end
        end
        for i = 1, #idx.uses do
            if idx.uses[i].anchor == target then
                local sym = symbol_by_id(idx, idx.uses[i].symbol_id)
                if sym then return C.AnchorSymbol(sym, C.RoleUse) end
            end
        end
        for i = 1, #idx.unresolved do
            if idx.unresolved[i].anchor == target then
                return C.AnchorUnresolved(idx.unresolved[i].name)
            end
        end
        return C.AnchorMissing
    end)

    local type_target = pvm.phase("type_target", function(q)
        local env = resolve_named_types(q.doc)
        for i = 1, #env.classes do
            local cls = env.classes[i]
            if cls.name == q.name then return C.TypeClassTarget(q.name, cls.anchor, cls) end
        end
        for i = 1, #env.aliases do
            local a = env.aliases[i]
            if a.name == q.name then return C.TypeAliasTarget(q.name, a.anchor, a) end
        end
        for i = 1, #env.generics do
            local g = env.generics[i]
            if g.name == q.name then return C.TypeGenericTarget(q.name, g.anchor, g) end
        end
        if BUILTIN_TYPES[q.name] then return C.TypeBuiltinTarget(q.name) end
        return C.TypeTargetMissing
    end)

    local goto_definition = pvm.phase("goto_definition", function(q)
        if not q.subject or q.subject.kind == "QueryMissing" then
            return C.DefMiss(C.DefMetaMissing)
        end
        if q.subject.kind == "QueryTypeName" then
            local tt = pvm.one(type_target(C.TypeNameQuery(q.doc, q.subject.name)))
            if tt.kind ~= "TypeTargetMissing" and tt.anchor then
                return C.DefHit(tt.anchor, C.DefMetaType(tt))
            end
            return C.DefMiss(tt.kind ~= "TypeTargetMissing" and C.DefMetaType(tt) or C.DefMetaMissing)
        end
        local binding = pvm.one(symbol_for_anchor(C.SubjectQuery(q.doc, q.subject)))
        if binding.kind == "AnchorSymbol" then
            local d = pvm.drain(definitions_of(C.SymbolIdQuery(q.doc, binding.symbol.id)))
            if #d > 0 then return C.DefHit(d[1].anchor, C.DefMetaSymbol(binding.role, binding.symbol, d)) end
            return C.DefMiss(C.DefMetaSymbol(binding.role, binding.symbol, d))
        end
        if binding.kind == "AnchorUnresolved" then
            return C.DefMiss(C.DefMetaUnresolved(binding.name))
        end
        return C.DefMiss(C.DefMetaMissing)
    end)

    local find_references = pvm.phase("find_references", {
        [C.RefQuery] = function(q)
            if not q.subject or q.subject.kind == "QueryMissing" then return pvm.empty() end
            if q.subject.kind == "QueryTypeName" then
                local tt = pvm.one(type_target(C.TypeNameQuery(q.doc, q.subject.name)))
                if q.include_declaration and tt.kind ~= "TypeTargetMissing" and tt.anchor then
                    return pvm.once(C.Occurrence("type:" .. type_target_kind(tt) .. ":" .. tt.name,
                        tt.name, type_target_symbol_kind(tt), tt.anchor))
                end
                return pvm.empty()
            end
            local binding = pvm.one(symbol_for_anchor(C.SubjectQuery(q.doc, q.subject)))
            if binding.kind ~= "AnchorSymbol" then return pvm.empty() end
            if q.include_declaration then
                local g1, p1, c1 = definitions_of(C.SymbolIdQuery(q.doc, binding.symbol.id))
                local g2, p2, c2 = references_of(C.SymbolIdQuery(q.doc, binding.symbol.id))
                return pvm.concat2(g1, p1, c1, g2, p2, c2)
            end
            return references_of(C.SymbolIdQuery(q.doc, binding.symbol.id))
        end,
    })

    local hover = pvm.phase("hover", function(q)
        if not q.subject or q.subject.kind == "QueryMissing" then return C.HoverMissing end
        if q.subject.kind == "QueryTypeName" then
            local tt = pvm.one(type_target(C.TypeNameQuery(q.doc, q.subject.name)))
            if tt.kind == "TypeTargetMissing" then return C.HoverType(q.subject.name, "unknown type", 0) end
            if tt.kind == "TypeClassTarget" then return C.HoverType(tt.name, "class", #tt.value.fields) end
            if tt.kind == "TypeAliasTarget" then return C.HoverType(tt.name, "alias", 0) end
            if tt.kind == "TypeGenericTarget" then return C.HoverType(tt.name, "generic", 0) end
            return C.HoverType(tt.name, type_target_kind(tt), 0)
        end
        local binding = pvm.one(symbol_for_anchor(C.SubjectQuery(q.doc, q.subject)))
        if binding.kind == "AnchorSymbol" then
            local nd = #pvm.drain(definitions_of(C.SymbolIdQuery(q.doc, binding.symbol.id)))
            local nu = #pvm.drain(references_of(C.SymbolIdQuery(q.doc, binding.symbol.id)))
            local sym = binding.symbol
            return C.HoverSymbol(binding.role, sym.name, sym.kind, sym.scope, nd, nu, C.TUnknown)
        end
        if binding.kind == "AnchorUnresolved" then
            return C.HoverUnresolved(binding.name, "undefined global")
        end
        return C.HoverMissing
    end)

    -- ── Public engine ──────────────────────────────────────

    local engine = {
        context = ctx,
        C = C,
        collect_doc_types = collect_doc_types,
        scope_events = scope_events,
        item_scope_events_phase = item_scope_events,
        file_scope_events_phase = file_scope_events,
        item_scope_summary_phase = item_scope_summary,
        item_type_env_phase = item_type_env,
        item_unknown_type_diagnostics_phase = item_unknown_type_diagnostics,
        item_semantics_phase = item_semantics,
        semantic_doc_phase = semantic_doc,
        item_symbol_index_phase = item_symbol_index,
        definitions_of_phase = definitions_of,
        references_of_phase = references_of,
        symbol_for_anchor_phase = symbol_for_anchor,
        type_target_phase = type_target,
        goto_definition_phase = goto_definition,
        find_references_phase = find_references,
        hover_phase = hover,
    }

    local function unwrap1(a, b)
        if pvm.classof(a) then return a end
        return b
    end

    local function unwrap2(a, b, c)
        if pvm.classof(a) then return a, b end
        return b, c
    end

    local function unwrap3(a, b, c, d)
        if pvm.classof(a) then return a, b, c end
        return b, c, d
    end

    engine.report_string = function()
        return pvm.report_string({
            engine.collect_doc_types,
            engine.scope_events,
            engine.item_scope_events_phase,
            engine.file_scope_events_phase,
            engine.item_scope_summary_phase,
            engine.item_type_env_phase,
            engine.item_unknown_type_diagnostics_phase,
            engine.item_semantics_phase,
            engine.semantic_doc_phase,
            engine.item_symbol_index_phase,
            engine.definitions_of_phase,
            engine.references_of_phase,
            engine.symbol_for_anchor_phase,
            engine.type_target_phase,
            engine.goto_definition_phase,
            engine.find_references_phase,
            engine.hover_phase,
        })
    end

    engine.compile = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(semantic_doc(doc))
    end

    engine.resolve_named_types = function(a, b)
        local file = unwrap1(a, b)
        return resolve_named_types(file)
    end
    engine.item_scope_events = function(a, b)
        local item = unwrap1(a, b)
        return item_scope_events(item)
    end
    engine.file_scope_events = function(a, b)
        local file = unwrap1(a, b)
        return file_scope_events(file)
    end
    engine.item_scope_summary = function(a, b)
        local item = unwrap1(a, b)
        return item_scope_summary(item)
    end
    engine.scope_diagnostics = function(a, b)
        local file = unwrap1(a, b)
        return scope_diagnostics(file)
    end
    engine.diagnostics = function(a, b)
        local file = unwrap1(a, b)
        return diagnostics(file)
    end
    engine.index = function(a, b)
        local file = unwrap1(a, b)
        return symbol_index(file)
    end
    engine.definitions_of = function(a, b, c)
        local file, sid = unwrap2(a, b, c)
        return definitions_of(C.SymbolIdQuery(file, sid))
    end
    engine.references_of = function(a, b, c)
        local file, sid = unwrap2(a, b, c)
        return references_of(C.SymbolIdQuery(file, sid))
    end

    engine.symbol_for_anchor = function(a, b, c)
        local file, anchor = unwrap2(a, b, c)
        return symbol_for_anchor(C.SubjectQuery(file, C.QueryAnchor(anchor_ref(C, anchor))))
    end

    engine.type_target = function(a, b, c)
        local file, name = unwrap2(a, b, c)
        return type_target(C.TypeNameQuery(file, name))
    end

    engine.goto_definition = function(a, b, c)
        local file, v = unwrap2(a, b, c)
        return goto_definition(C.SubjectQuery(file, query_subject(v)))
    end

    engine.find_references = function(a, b, c, d)
        local file, v, include_decl = unwrap3(a, b, c, d)
        return find_references(C.RefQuery(file, query_subject(v), include_decl and true or false))
    end

    engine.hover = function(a, b, c)
        local file, v = unwrap2(a, b, c)
        return hover(C.SubjectQuery(file, query_subject(v)))
    end

    engine.reset = function()
        collect_doc_types:reset()
        scope_events:reset()
        item_scope_events:reset()
        file_scope_events:reset()
        item_scope_summary:reset()
        item_type_env:reset()
        item_unknown_type_diagnostics:reset()
        item_symbol_index:reset()
        item_semantics:reset()
        semantic_doc:reset()
        definitions_of:reset()
        references_of:reset()
        symbol_for_anchor:reset()
        type_target:reset()
        goto_definition:reset()
        find_references:reset()
        hover:reset()
    end

    return engine
end

return M
