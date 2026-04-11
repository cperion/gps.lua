-- lsp/semantics.lua
--
-- Semantic boundaries over the Lua AST (ASDL layer).
--
-- Phases (streaming, per-node cached):
--   collect_doc_types  — File → DocEvent* (DClass, DField, DAlias, ...)
--   scope_events       — File → ScopeEvent* (Enter/Exit/Decl/Ref/Write)
--
-- Lowers (single value, cached per node identity):
--   resolve_named_types — File → TypeEnv
--   item_scope_events  — Item → ScopeEventList
--   file_scope_events   — File → ScopeEventList
--   scope_diagnostics   — File → DiagnosticSet
--   symbol_index        — File → SymbolIndex
--   diagnostics         — File → DiagnosticSet
--   definitions_of      — SymbolIdQuery → OccurrenceList
--   references_of       — SymbolIdQuery → OccurrenceList
--   symbol_for_anchor   — SubjectQuery → AnchorBinding
--   type_target         — TypeNameQuery → TypeTarget
--   goto_definition     — SubjectQuery → DefinitionResult
--   find_references     — RefQuery → ReferenceResult
--   hover               — SubjectQuery → HoverInfo

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
}

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

    -- ── collect_doc_types phase ────────────────────────────
    local collect_doc_types
    collect_doc_types = pvm.phase("collect_doc_types", {
        [C.File] = function(n)
            return pvm.children(collect_doc_types, n.items)
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
        [C.File] = function(n)
            local g1, p1, c1 = pvm.once(C.ScopeEnter("file", anchor_ref(C, n)))
            local g2, p2, c2 = pvm.children(scope_events, n.items)
            local g3, p3, c3 = pvm.once(C.ScopeExit("file", anchor_ref(C, n)))
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
            append_trip(trips, pvm.once(C.ScopeEnter("function", anchor_ref(C, n))))
            for i = 1, #n.params do
                append_trip(trips, pvm.once(C.ScopeDeclLocal("param", n.params[i].name, anchor_ref(C, n.params[i]))))
            end
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit("function", anchor_ref(C, n))))
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
                append_trip(trips, pvm.once(C.ScopeDeclLocal("local", n.names[i].value, anchor_ref(C, n.names[i]))))
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
            local g1, p1, c1 = pvm.once(C.ScopeDeclLocal("local", n.name, anchor_ref(C, n)))
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
                append_trip(trips, pvm.once(C.ScopeEnter("if", anchor_ref(C, arm))))
                append_trip(trips, scope_events(arm.body))
                append_trip(trips, pvm.once(C.ScopeExit("if", anchor_ref(C, arm))))
            end
            if n.else_block then
                append_trip(trips, pvm.once(C.ScopeEnter("else", anchor_ref(C, n.else_block))))
                append_trip(trips, scope_events(n.else_block))
                append_trip(trips, pvm.once(C.ScopeExit("else", anchor_ref(C, n.else_block))))
            end
            return pvm.concat_all(trips)
        end,

        [C.While] = function(n)
            local trips = {}
            append_trip(trips, scope_events(n.cond))
            append_trip(trips, pvm.once(C.ScopeEnter("while", anchor_ref(C, n))))
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit("while", anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.Repeat] = function(n)
            local trips = {}
            append_trip(trips, pvm.once(C.ScopeEnter("repeat", anchor_ref(C, n))))
            append_trip(trips, scope_events(n.body))
            append_trip(trips, scope_events(n.cond))
            append_trip(trips, pvm.once(C.ScopeExit("repeat", anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.ForNum] = function(n)
            local trips = {}
            append_trip(trips, scope_events(n.init))
            append_trip(trips, scope_events(n.limit))
            append_trip(trips, scope_events(n.step))
            append_trip(trips, pvm.once(C.ScopeEnter("for", anchor_ref(C, n))))
            append_trip(trips, pvm.once(C.ScopeDeclLocal("local", n.name, anchor_ref(C, n))))
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit("for", anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.ForIn] = function(n)
            local trips = {}
            for i = 1, #n.iter do append_trip(trips, scope_events(n.iter[i])) end
            append_trip(trips, pvm.once(C.ScopeEnter("for", anchor_ref(C, n))))
            for i = 1, #n.names do
                append_trip(trips, pvm.once(C.ScopeDeclLocal("local", n.names[i].value, anchor_ref(C, n.names[i]))))
            end
            append_trip(trips, scope_events(n.body))
            append_trip(trips, pvm.once(C.ScopeExit("for", anchor_ref(C, n))))
            return pvm.concat_all(trips)
        end,

        [C.Do] = function(n)
            local g1, p1, c1 = pvm.once(C.ScopeEnter("do", anchor_ref(C, n)))
            local g2, p2, c2 = scope_events(n.body)
            local g3, p3, c3 = pvm.once(C.ScopeExit("do", anchor_ref(C, n)))
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

    -- ── resolve_named_types lower ──────────────────────────

    local resolve_named_types = pvm.lower("resolve_named_types", function(file)
        local events = pvm.drain(collect_doc_types(file))
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

        for i = 1, #events do
            local e = events[i]
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

        return C.TypeEnv(classes, aliases, generics)
    end)

    -- ── item_scope_events lower ────────────────────────────
    -- Converts the flat NameOcc array (extracted at parse time)
    -- into ScopeEvent nodes. No tree walking — just array iteration.
    -- Cached per Item identity.

    -- ── item_scope_events lower ────────────────────────────
    -- Extracts scope events from an Item by walking its Stmt tree.
    -- Pure Lua walk (no pvm phase overhead per AST node).
    -- Cached per Item identity.

    local item_scope_events = pvm.lower("item_scope_events", function(item)
        local out, n = {}, 0
        local function emit(ev) n = n + 1; out[n] = ev end
        local aref = anchor_ref(C, item)

        local walk_expr, walk_stmt, walk_body, walk_block

        function walk_expr(e)
            if not e then return end
            local k = e.kind
            if k == "NameRef" then emit(C.ScopeRef(e.name, aref))
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
            if lv.kind == "LName" then emit(C.ScopeWrite(lv.name, aref))
            elseif lv.kind == "LField" then walk_expr(lv.base)
            elseif lv.kind == "LIndex" then walk_expr(lv.base); walk_expr(lv.key)
            elseif lv.kind == "LMethod" then walk_expr(lv.base) end
        end

        function walk_block(block)
            for i = 1, #block.items do walk_stmt(block.items[i].stmt) end
        end

        function walk_body(body)
            emit(C.ScopeEnter("function", aref))
            for i = 1, #body.params do
                emit(C.ScopeDeclLocal("param", body.params[i].name, aref))
            end
            walk_block(body.body)
            emit(C.ScopeExit("function", aref))
        end

        function walk_stmt(s)
            if not s then return end
            local k = s.kind
            if k == "LocalAssign" then
                for i = 1, #s.values do walk_expr(s.values[i]) end
                for i = 1, #s.names do emit(C.ScopeDeclLocal("local", s.names[i].value, aref)) end
            elseif k == "Assign" then
                for i = 1, #s.rhs do walk_expr(s.rhs[i]) end
                for i = 1, #s.lhs do walk_lvalue(s.lhs[i]) end
            elseif k == "LocalFunction" then
                emit(C.ScopeDeclLocal("local", s.name, aref))
                walk_body(s.body)
            elseif k == "Function" then
                if s.name.kind == "LName" then emit(C.ScopeWrite(s.name.name, aref))
                elseif s.name.kind == "LField" then walk_expr(s.name.base)
                elseif s.name.kind == "LIndex" then walk_expr(s.name.base); walk_expr(s.name.key)
                elseif s.name.kind == "LMethod" then walk_expr(s.name.base) end
                walk_body(s.body)
            elseif k == "Return" then
                for i = 1, #s.values do walk_expr(s.values[i]) end
            elseif k == "CallStmt" then
                walk_expr(s.callee)
                for i = 1, #s.args do walk_expr(s.args[i]) end
            elseif k == "If" then
                for i = 1, #s.arms do
                    walk_expr(s.arms[i].cond)
                    emit(C.ScopeEnter("if", aref))
                    walk_block(s.arms[i].body)
                    emit(C.ScopeExit("if", aref))
                end
                if s.else_block then
                    emit(C.ScopeEnter("else", aref))
                    walk_block(s.else_block)
                    emit(C.ScopeExit("else", aref))
                end
            elseif k == "While" then
                walk_expr(s.cond)
                emit(C.ScopeEnter("while", aref))
                walk_block(s.body)
                emit(C.ScopeExit("while", aref))
            elseif k == "Repeat" then
                emit(C.ScopeEnter("repeat", aref))
                walk_block(s.body)
                walk_expr(s.cond)
                emit(C.ScopeExit("repeat", aref))
            elseif k == "ForNum" then
                walk_expr(s.init); walk_expr(s.limit); walk_expr(s.step)
                emit(C.ScopeEnter("for", aref))
                emit(C.ScopeDeclLocal("local", s.name, aref))
                walk_block(s.body)
                emit(C.ScopeExit("for", aref))
            elseif k == "ForIn" then
                for i = 1, #s.iter do walk_expr(s.iter[i]) end
                emit(C.ScopeEnter("for", aref))
                for i = 1, #s.names do emit(C.ScopeDeclLocal("local", s.names[i].value, aref)) end
                walk_block(s.body)
                emit(C.ScopeExit("for", aref))
            elseif k == "Do" then
                emit(C.ScopeEnter("do", aref))
                walk_block(s.body)
                emit(C.ScopeExit("do", aref))
            end
        end

        walk_stmt(item.stmt)
        return C.ScopeEventList(out)
    end)

    -- ── file_scope_events lower ────────────────────────────
    -- Assembles per-item scope events into a file-level stream.
    -- Each item's scope is a flat NameOcc array — no tree walking.

    local file_scope_events = pvm.lower("file_scope_events", function(file)
        local out, n = {}, 0
        n = n + 1; out[n] = C.ScopeEnter("file", anchor_ref(C, file))

        for i = 1, #file.items do
            local ev = item_scope_events(file.items[i]).items
            for j = 1, #ev do n = n + 1; out[n] = ev[j] end
        end

        n = n + 1; out[n] = C.ScopeExit("file", anchor_ref(C, file))
        return C.ScopeEventList(out)
    end)

    -- ── scope_diagnostics lower ────────────────────────────

    local scope_diagnostics = pvm.lower("scope_diagnostics", function(file)
        local out, n = {}, 0
        local events = file_scope_events(file).items
        local scopes = {}
        local global_declared = {}
        local seen_undef = {}

        local function current_scope() return scopes[#scopes] end

        local function push_scope(kind)
            scopes[#scopes + 1] = C.ScopeDiagFrame(kind, {})
        end

        local function find_local_in_frame(frame, name)
            for i = 1, #frame.locals do
                if frame.locals[i].name == name then return frame.locals[i], i end
            end
            return nil, nil
        end

        local function find_local(name)
            for i = #scopes, 1, -1 do
                local info, j = find_local_in_frame(scopes[i], name)
                if info then return info, i, j end
            end
            return nil, nil, nil
        end

        local function replace_local(frame, idx, info)
            local locals = {}
            for i = 1, #frame.locals do
                locals[i] = (i == idx) and info or frame.locals[i]
            end
            return C.ScopeDiagFrame(frame.scope, locals)
        end

        local function add_diag(code, message, name, scope_kind, anchor)
            n = n + 1
            out[n] = C.Diagnostic(code, message, name or "", scope_kind or "", anchor_ref(C, anchor or file))
        end

        local function pop_scope()
            local scope = scopes[#scopes]
            if not scope then return end
            scopes[#scopes] = nil
            for i = 1, #scope.locals do
                local info = scope.locals[i]
                if info.used == 0 and info.name ~= "_" and info.name:sub(1, 1) ~= "_" then
                    local code = (info.decl_kind == "param") and "unused-param" or "unused-local"
                    add_diag(code, code:gsub("-", " ") .. " '" .. info.name .. "'",
                        info.name, scope.scope, info.anchor)
                end
            end
        end

        local function declare_local(name, kind, anchor)
            local scope = current_scope()
            if not scope then return end
            if find_local_in_frame(scope, name) then
                add_diag("redeclare-local", "local '" .. name .. "' redeclared in same scope",
                    name, scope.scope, anchor)
                return
            end
            local outer_hit = false
            for i = #scopes - 1, 1, -1 do
                if find_local_in_frame(scopes[i], name) then outer_hit = true; break end
            end
            if outer_hit then
                add_diag("shadowing-local", "local '" .. name .. "' shadows outer local",
                    name, scope.scope, anchor)
            elseif BUILTIN_GLOBALS[name] or contains_name(global_declared, name) then
                add_diag("shadowing-global", "local '" .. name .. "' shadows global",
                    name, scope.scope, anchor)
            end
            local locals = {}
            for i = 1, #scope.locals do locals[i] = scope.locals[i] end
            locals[#locals + 1] = C.ScopeLocalState(name, kind, 0, anchor_ref(C, anchor or file))
            scopes[#scopes] = C.ScopeDiagFrame(scope.scope, locals)
        end

        local function mark_ref(name, anchor)
            local info, sidx, lidx = find_local(name)
            if info then
                scopes[sidx] = replace_local(scopes[sidx], lidx,
                    C.ScopeLocalState(info.name, info.decl_kind, info.used + 1, info.anchor))
                return
            end
            if BUILTIN_GLOBALS[name] or contains_name(global_declared, name) then return end
            if not contains_name(seen_undef, name) then
                add_name_unique(seen_undef, name)
                local scope = current_scope()
                add_diag("undefined-global", "undefined global '" .. name .. "'",
                    name, scope and scope.scope or "?", anchor)
            end
        end

        for i = 1, #events do
            local e = events[i]
            local ek = e.kind
            if     ek == "ScopeEnter"      then push_scope(e.scope)
            elseif ek == "ScopeExit"       then pop_scope()
            elseif ek == "ScopeDeclLocal"  then declare_local(e.name, e.decl_kind or "local", e.anchor)
            elseif ek == "ScopeDeclGlobal" then add_name_unique(global_declared, e.name)
            elseif ek == "ScopeWrite"      then
                if not find_local(e.name) then add_name_unique(global_declared, e.name) end
            elseif ek == "ScopeRef"        then mark_ref(e.name, e.anchor)
            end
        end

        return C.DiagnosticSet(out)
    end)

    -- ── symbol_index lower ─────────────────────────────────

    local symbol_index = pvm.lower("symbol_index", function(file)
        local symbols, defs, uses, unresolved = {}, {}, {}, {}
        local events = file_scope_events(file).items
        local scopes = {}
        local scope_seq = 0
        local globals = {}

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
            defs[#defs + 1] = C.Occurrence(sym.id, sym.name, sym.kind, anchor_ref(C, anchor or file))
        end

        local function add_use(sym, anchor)
            uses[#uses + 1] = C.Occurrence(sym.id, sym.name, sym.kind, anchor_ref(C, anchor or file))
        end

        local function push_scope(kind, anchor)
            scope_seq = scope_seq + 1
            local id = kind .. ":" .. tostring(anchor or file) .. ":" .. tostring(scope_seq)
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
            local sym = add_symbol("builtin:" .. name, "builtin", name, "file", "file",
                anchor_ref(C, "builtin:" .. name))
            globals[#globals + 1] = sym
            return sym
        end

        local function ensure_global(name, anchor)
            local hit = find_global(name)
            if hit then return hit end
            local danchor = anchor_ref(C, anchor or ("global:" .. name))
            local sym = add_symbol("global:" .. name, "global", name, "file", "file", danchor)
            globals[#globals + 1] = sym
            add_def(sym, danchor)
            return sym
        end

        local function declare_local(name, decl_kind, anchor)
            local scope = current_scope()
            if not scope then return nil end
            local danchor = anchor_ref(C, anchor or (scope.id .. ":" .. name))
            local sym = add_symbol(danchor.id, decl_kind, name, scope.scope, scope.id, danchor)
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
            unresolved[#unresolved + 1] = C.Unresolved(name, anchor_ref(C, anchor or file))
        end

        local function write_name(name, anchor)
            local s = find_local(name)
            if s then add_use(s, anchor) else ensure_global(name, anchor) end
        end

        for i = 1, #events do
            local e = events[i]
            local ek = e.kind
            if     ek == "ScopeEnter"      then push_scope(e.scope, e.anchor)
            elseif ek == "ScopeExit"       then pop_scope()
            elseif ek == "ScopeDeclLocal"  then declare_local(e.name, e.decl_kind or "local", e.anchor)
            elseif ek == "ScopeDeclGlobal" then ensure_global(e.name, e.anchor)
            elseif ek == "ScopeRef"        then ref_name(e.name, e.anchor)
            elseif ek == "ScopeWrite"      then write_name(e.name, e.anchor)
            end
        end

        return C.SymbolIndex(symbols, defs, uses, unresolved)
    end)

    -- ── diagnostics lower ──────────────────────────────────
    -- Combines scope diagnostics + unknown-type diagnostics from doc annotations.

    local diagnostics = pvm.lower("diagnostics", function(file)
        local out, n = {}, 0
        local function add(d) n = n + 1; out[n] = d end

        local sdiags = scope_diagnostics(file).items
        for i = 1, #sdiags do add(sdiags[i]) end

        local env = resolve_named_types(file)
        local known = {}
        for k in pairs(BUILTIN_TYPES) do add_name_unique(known, k) end
        for i = 1, #env.aliases  do add_name_unique(known, env.aliases[i].name) end
        for i = 1, #env.classes  do add_name_unique(known, env.classes[i].name) end
        for i = 1, #env.generics do add_name_unique(known, env.generics[i].name) end

        local seen = {}
        local function emit_unknown(tname, owner, anchor)
            if contains_name(known, tname) or contains_name(seen, tname) then return end
            add_name_unique(seen, tname)
            add(C.Diagnostic("unknown-type",
                "unknown type '" .. tname .. "' in " .. owner, tname, "type", anchor))
        end

        for i = 1, #env.classes do
            local cls = env.classes[i]
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
        for i = 1, #env.aliases do
            local a = env.aliases[i]
            local refs = {}; add_named_type_refs(a.typ, refs)
            for r = 1, #refs do emit_unknown(refs[r], "alias " .. a.name, a.anchor) end
        end

        return C.DiagnosticSet(out)
    end)

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
        if not v then return C.QueryMissing() end
        if type(v) == "table" and v.kind == "TNamed" then return C.QueryTypeName(v.name) end
        if type(v) == "string" then return C.QueryTypeName(v) end
        return C.QueryAnchor(anchor_ref(C, v))
    end

    local definitions_of = pvm.lower("definitions_of", function(q)
        local idx = symbol_index(q.file)
        local out = {}
        for i = 1, #idx.defs do
            if idx.defs[i].symbol_id == q.symbol_id then out[#out + 1] = idx.defs[i] end
        end
        return C.OccurrenceList(out)
    end)

    local references_of = pvm.lower("references_of", function(q)
        local idx = symbol_index(q.file)
        local out = {}
        for i = 1, #idx.uses do
            if idx.uses[i].symbol_id == q.symbol_id then out[#out + 1] = idx.uses[i] end
        end
        return C.OccurrenceList(out)
    end)

    local symbol_for_anchor = pvm.lower("symbol_for_anchor", function(q)
        if not q.subject or q.subject.kind ~= "QueryAnchor" then return C.AnchorMissing() end
        local target = q.subject.anchor
        local idx = symbol_index(q.file)

        for i = 1, #idx.defs do
            if idx.defs[i].anchor == target then
                local sym = symbol_by_id(idx, idx.defs[i].symbol_id)
                if sym then return C.AnchorSymbol(sym, "def") end
            end
        end
        for i = 1, #idx.uses do
            if idx.uses[i].anchor == target then
                local sym = symbol_by_id(idx, idx.uses[i].symbol_id)
                if sym then return C.AnchorSymbol(sym, "use") end
            end
        end
        for i = 1, #idx.unresolved do
            if idx.unresolved[i].anchor == target then
                return C.AnchorUnresolved(idx.unresolved[i].name)
            end
        end
        return C.AnchorMissing()
    end)

    local type_target = pvm.lower("type_target", function(q)
        local env = resolve_named_types(q.file)
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
        return C.TypeTargetMissing()
    end)

    local goto_definition = pvm.lower("goto_definition", function(q)
        if not q.subject or q.subject.kind == "QueryMissing" then
            return C.DefMiss(C.DefMetaMissing())
        end
        if q.subject.kind == "QueryTypeName" then
            local tt = type_target(C.TypeNameQuery(q.file, q.subject.name))
            if tt.kind ~= "TypeTargetMissing" and tt.anchor then
                return C.DefHit(tt.anchor, C.DefMetaType(tt))
            end
            return C.DefMiss(tt.kind ~= "TypeTargetMissing" and C.DefMetaType(tt) or C.DefMetaMissing())
        end
        local binding = symbol_for_anchor(C.SubjectQuery(q.file, q.subject))
        if binding.kind == "AnchorSymbol" then
            local d = definitions_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            if #d > 0 then return C.DefHit(d[1].anchor, C.DefMetaSymbol(binding.role, binding.symbol, d)) end
            return C.DefMiss(C.DefMetaSymbol(binding.role, binding.symbol, d))
        end
        if binding.kind == "AnchorUnresolved" then
            return C.DefMiss(C.DefMetaUnresolved(binding.name))
        end
        return C.DefMiss(C.DefMetaMissing())
    end)

    local find_references = pvm.lower("find_references", function(q)
        local refs = {}
        if not q.subject or q.subject.kind == "QueryMissing" then return C.ReferenceResult(refs) end
        if q.subject.kind == "QueryTypeName" then
            local tt = type_target(C.TypeNameQuery(q.file, q.subject.name))
            if q.include_declaration and tt.kind ~= "TypeTargetMissing" and tt.anchor then
                refs[#refs + 1] = C.Occurrence("type:" .. type_target_kind(tt) .. ":" .. tt.name,
                    tt.name, type_target_kind(tt), tt.anchor)
            end
            return C.ReferenceResult(refs)
        end
        local binding = symbol_for_anchor(C.SubjectQuery(q.file, q.subject))
        if binding.kind ~= "AnchorSymbol" then return C.ReferenceResult(refs) end
        if q.include_declaration then
            local d = definitions_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            for i = 1, #d do refs[#refs + 1] = d[i] end
        end
        local u = references_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
        for i = 1, #u do refs[#refs + 1] = u[i] end
        return C.ReferenceResult(refs)
    end)

    local hover = pvm.lower("hover", function(q)
        if not q.subject or q.subject.kind == "QueryMissing" then return C.HoverMissing() end
        if q.subject.kind == "QueryTypeName" then
            local tt = type_target(C.TypeNameQuery(q.file, q.subject.name))
            if tt.kind == "TypeTargetMissing" then return C.HoverType(q.subject.name, "unknown type", 0) end
            if tt.kind == "TypeClassTarget" then return C.HoverType(tt.name, "class", #tt.value.fields) end
            if tt.kind == "TypeAliasTarget" then return C.HoverType(tt.name, "alias", 0) end
            if tt.kind == "TypeGenericTarget" then return C.HoverType(tt.name, "generic", 0) end
            return C.HoverType(tt.name, type_target_kind(tt), 0)
        end
        local binding = symbol_for_anchor(C.SubjectQuery(q.file, q.subject))
        if binding.kind == "AnchorSymbol" then
            local nd = #definitions_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            local nu = #references_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            local sym = binding.symbol
            return C.HoverSymbol(binding.role, sym.name, sym.kind, sym.scope, nd, nu, C.TUnknown())
        end
        if binding.kind == "AnchorUnresolved" then
            return C.HoverUnresolved(binding.name, "undefined global")
        end
        return C.HoverMissing()
    end)

    -- ── Public engine ──────────────────────────────────────

    local engine = {
        context = ctx,
        C = C,
        collect_doc_types = collect_doc_types,
        scope_events = scope_events,
        item_scope_events = item_scope_events,
        file_scope_events = file_scope_events,
        resolve_named_types = resolve_named_types,
        scope_diagnostics = scope_diagnostics,
        symbol_index = symbol_index,
        diagnostics = diagnostics,
        definitions_of_lower = definitions_of,
        references_of_lower = references_of,
        symbol_for_anchor_lower = symbol_for_anchor,
        type_target_lower = type_target,
        goto_definition_lower = goto_definition,
        find_references_lower = find_references,
        hover_lower = hover,
    }

    function engine:report_string()
        return pvm.report_string({
            self.collect_doc_types,
            self.scope_events,
            self.item_scope_events,
            self.file_scope_events,
            self.resolve_named_types,
            self.scope_diagnostics,
            self.symbol_index,
            self.diagnostics,
            self.definitions_of_lower,
            self.references_of_lower,
            self.symbol_for_anchor_lower,
            self.type_target_lower,
            self.goto_definition_lower,
            self.find_references_lower,
            self.hover_lower,
        })
    end

    function engine:index(file) return symbol_index(file) end
    function engine:definitions_of(file, sid) return definitions_of(C.SymbolIdQuery(file, sid)) end
    function engine:references_of(file, sid) return references_of(C.SymbolIdQuery(file, sid)) end

    function engine:symbol_for_anchor(file, anchor)
        return symbol_for_anchor(C.SubjectQuery(file, C.QueryAnchor(anchor_ref(C, anchor))))
    end

    function engine:type_target(file, name) return type_target(C.TypeNameQuery(file, name)) end

    function engine:goto_definition(file, v)
        return goto_definition(C.SubjectQuery(file, query_subject(v)))
    end

    function engine:find_references(file, v, include_decl)
        return find_references(C.RefQuery(file, query_subject(v), include_decl and true or false))
    end

    function engine:hover(file, v)
        return hover(C.SubjectQuery(file, query_subject(v)))
    end

    function engine:reset()
        collect_doc_types:reset()
        scope_events:reset()
        item_scope_events:reset()
        file_scope_events:reset()
        resolve_named_types:reset()
        scope_diagnostics:reset()
        symbol_index:reset()
        diagnostics:reset()
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
