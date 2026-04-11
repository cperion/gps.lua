-- bench/lua_lsp_semantics_v1.lua
--
-- First semantic boundaries over lua_lsp_asdl_v1:
--   - bind_symbols      (phase)
--   - collect_doc_types (phase)
--   - resolve_named_types (lower)
--   - diagnostics         (lower)

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("bench.lua_lsp_asdl_v1")

local M = {}

local BUILTIN_GLOBALS = {
    _G = true, _VERSION = true,
    assert = true, collectgarbage = true, dofile = true, error = true,
    getmetatable = true, ipairs = true, load = true, loadfile = true,
    next = true, pairs = true, pcall = true, print = true, rawequal = true,
    rawget = true, rawlen = true, rawset = true, require = true,
    select = true, setmetatable = true, tonumber = true, tostring = true,
    type = true, xpcall = true,
    math = true, string = true, table = true, coroutine = true,
    io = true, os = true, debug = true, package = true, utf8 = true,
}

local BUILTIN_TYPES = {
    any = true, unknown = true,
    ["nil"] = true, boolean = true, number = true, string = true,
    table = true, ["function"] = true, thread = true, userdata = true,
}

local function append_trip(trips, g, p, c)
    trips[#trips + 1] = { g, p, c }
end

local function anchor_ref(C, v)
    if not v then return nil end
    if type(v) == "table" then
        local tv = tostring(v)
        if tv:match("^LuaLsp%.AnchorRef%(") then return v end
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
        add_name_unique(out, typ.name)
        return
    end

    if k == "TUnion" or k == "TIntersect" then
        for i = 1, #typ.parts do add_named_type_refs(typ.parts[i], out) end
        return
    end

    if k == "TTuple" then
        for i = 1, #typ.items do add_named_type_refs(typ.items[i], out) end
        return
    end

    if k == "TArray" or k == "TOptional" or k == "TVararg" or k == "TParen" then
        add_named_type_refs(typ.inner or typ.item, out)
        return
    end

    if k == "TMap" then
        add_named_type_refs(typ.key, out)
        add_named_type_refs(typ.value, out)
        return
    end

    if k == "TFunc" then
        local sig = typ.sig
        if sig then
            for i = 1, #sig.params do add_named_type_refs(sig.params[i], out) end
            for i = 1, #sig.returns do add_named_type_refs(sig.returns[i], out) end
        end
        return
    end

    if k == "TTable" then
        for i = 1, #typ.fields do
            add_named_type_refs(typ.fields[i].typ, out)
        end
        return
    end
end

function M.new(ctx)
    ctx = ctx or ASDL.context()
    local C = ctx.LuaLsp

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

    local bind_symbols
    bind_symbols = pvm.phase("bind_symbols", {
        [C.File] = function(n)
            return pvm.children(bind_symbols, n.items)
        end,

        [C.Item] = function(n)
            return bind_symbols(n.stmt)
        end,

        [C.Block] = function(n)
            return pvm.children(bind_symbols, n.items)
        end,

        [C.Name] = function(n)
            return pvm.once(C.ScopeDeclLocal("local", n.value, anchor_ref(C, n)))
        end,

        [C.PName] = function(n)
            return pvm.once(C.ScopeDeclLocal("param", n.name, anchor_ref(C, n)))
        end,

        [C.FuncBody] = function(n)
            local g1, p1, c1 = pvm.children(bind_symbols, n.params)
            local g2, p2, c2 = bind_symbols(n.body)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.LocalAssign] = function(n)
            local g1, p1, c1 = pvm.children(bind_symbols, n.names)
            local g2, p2, c2 = pvm.children(bind_symbols, n.values)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.LocalFunction] = function(n)
            local g1, p1, c1 = pvm.once(C.ScopeDeclLocal("local", n.name, anchor_ref(C, n)))
            local g2, p2, c2 = bind_symbols(n.body)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Function] = function(n)
            local trips = {}
            if n.name.kind == "LName" then
                append_trip(trips, pvm.once(C.ScopeDeclGlobal(n.name.name, anchor_ref(C, n.name))))
            else
                append_trip(trips, bind_symbols(n.name))
            end
            append_trip(trips, bind_symbols(n.body))
            return pvm.concat_all(trips)
        end,

        [C.Assign] = function(n)
            local g1, p1, c1 = pvm.children(bind_symbols, n.lhs)
            local g2, p2, c2 = pvm.children(bind_symbols, n.rhs)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Return] = function(n)
            return pvm.children(bind_symbols, n.values)
        end,

        [C.CallStmt] = function(n)
            local g1, p1, c1 = bind_symbols(n.callee)
            local g2, p2, c2 = pvm.children(bind_symbols, n.args)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.If] = function(n)
            local trips = {}
            append_trip(trips, pvm.children(bind_symbols, n.arms))
            if n.else_block then append_trip(trips, bind_symbols(n.else_block)) end
            return pvm.concat_all(trips)
        end,

        [C.CondBlock] = function(n)
            local g1, p1, c1 = bind_symbols(n.cond)
            local g2, p2, c2 = bind_symbols(n.body)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.While] = function(n)
            local g1, p1, c1 = bind_symbols(n.cond)
            local g2, p2, c2 = bind_symbols(n.body)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Repeat] = function(n)
            local g1, p1, c1 = bind_symbols(n.body)
            local g2, p2, c2 = bind_symbols(n.cond)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.ForNum] = function(n)
            local trips = {}
            append_trip(trips, pvm.once(C.ScopeDeclLocal("local", n.name, anchor_ref(C, n))))
            append_trip(trips, bind_symbols(n.init))
            append_trip(trips, bind_symbols(n.limit))
            append_trip(trips, bind_symbols(n.step))
            append_trip(trips, bind_symbols(n.body))
            return pvm.concat_all(trips)
        end,

        [C.ForIn] = function(n)
            local g1, p1, c1 = pvm.children(bind_symbols, n.names)
            local g2, p2, c2 = pvm.children(bind_symbols, n.iter)
            local g3, p3, c3 = bind_symbols(n.body)
            return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
        end,

        [C.Do] = function(n)
            return bind_symbols(n.body)
        end,

        [C.Break] = function()
            return pvm.empty()
        end,

        [C.Goto] = function()
            return pvm.empty()
        end,

        [C.Label] = function()
            return pvm.empty()
        end,

        [C.LName] = function()
            return pvm.empty()
        end,

        [C.LField] = function(n)
            return bind_symbols(n.base)
        end,

        [C.LIndex] = function(n)
            local g1, p1, c1 = bind_symbols(n.base)
            local g2, p2, c2 = bind_symbols(n.key)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Nil] = function() return pvm.empty() end,
        [C.Bool] = function() return pvm.empty() end,
        [C.Number] = function() return pvm.empty() end,
        [C.String] = function() return pvm.empty() end,
        [C.Vararg] = function() return pvm.empty() end,

        [C.NameRef] = function(n)
            return pvm.once(C.ScopeRef(n.name, anchor_ref(C, n)))
        end,

        [C.Field] = function(n)
            return bind_symbols(n.base)
        end,

        [C.Index] = function(n)
            local g1, p1, c1 = bind_symbols(n.base)
            local g2, p2, c2 = bind_symbols(n.key)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Call] = function(n)
            local g1, p1, c1 = bind_symbols(n.callee)
            local g2, p2, c2 = pvm.children(bind_symbols, n.args)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.MethodCall] = function(n)
            local g1, p1, c1 = bind_symbols(n.recv)
            local g2, p2, c2 = pvm.children(bind_symbols, n.args)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.FunctionExpr] = function(n)
            return bind_symbols(n.body)
        end,

        [C.TableCtor] = function(n)
            return pvm.children(bind_symbols, n.fields)
        end,

        [C.Unary] = function(n)
            return bind_symbols(n.value)
        end,

        [C.Binary] = function(n)
            local g1, p1, c1 = bind_symbols(n.lhs)
            local g2, p2, c2 = bind_symbols(n.rhs)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.Paren] = function(n)
            return bind_symbols(n.inner)
        end,

        [C.ArrayField] = function(n)
            return bind_symbols(n.value)
        end,

        [C.PairField] = function(n)
            local g1, p1, c1 = bind_symbols(n.key)
            local g2, p2, c2 = bind_symbols(n.value)
            return pvm.concat2(g1, p1, c1, g2, p2, c2)
        end,

        [C.NameField] = function(n)
            return bind_symbols(n.value)
        end,
    })

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

        [C.Nil] = function() return pvm.empty() end,
        [C.Bool] = function() return pvm.empty() end,
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

    local resolve_named_types = pvm.lower("resolve_named_types", function(file)
        local events = pvm.drain(collect_doc_types(file))

        local classes, aliases, generics = {}, {}, {}
        local current_class = nil

        local function index_of_class(name)
            for i = 1, #classes do
                if classes[i].name == name then return i end
            end
            return nil
        end

        local function index_of_alias(name)
            for i = 1, #aliases do
                if aliases[i].name == name then return i end
            end
            return nil
        end

        local function index_of_generic(name)
            for i = 1, #generics do
                if generics[i].name == name then return i end
            end
            return nil
        end

        local function upsert_class(name, extends, anchor)
            local idx = index_of_class(name)
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
                local f = cls.fields[i]
                if f.name == field.name then
                    fields[#fields + 1] = field
                    replaced = true
                else
                    fields[#fields + 1] = f
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
                    local cidx = index_of_class(current_class)
                    if cidx then
                        local cls = classes[cidx]
                        local field = C.TypeClassField(e.name, e.typ, e.optional, e.anchor)
                        classes[cidx] = add_or_replace_field(cls, field)
                    end
                end

            elseif k == "DAlias" then
                local alias = C.TypeAlias(e.name, e.typ, e.anchor)
                local aidx = index_of_alias(e.name)
                if aidx then aliases[aidx] = alias else aliases[#aliases + 1] = alias end
                current_class = nil

            elseif k == "DGeneric" then
                local generic = C.TypeGeneric(e.name, e.bounds, e.anchor)
                local gidx = index_of_generic(e.name)
                if gidx then generics[gidx] = generic else generics[#generics + 1] = generic end
            end
        end

        return C.TypeEnv(classes, aliases, generics)
    end)

    local item_scope_summary = pvm.lower("item_scope_summary", function(item)
        return C.ScopeEventList(pvm.drain(scope_events(item)))
    end)

    local file_scope_events = pvm.lower("file_scope_events", function(file)
        local out, n = {}, 0

        n = n + 1
        out[n] = C.ScopeEnter("file", anchor_ref(C, file))

        for i = 1, #file.items do
            local ev = item_scope_summary(file.items[i]).items
            for j = 1, #ev do
                n = n + 1
                out[n] = ev[j]
            end
        end

        n = n + 1
        out[n] = C.ScopeExit("file", anchor_ref(C, file))

        return C.ScopeEventList(out)
    end)

    local scope_diagnostics = pvm.lower("scope_diagnostics", function(file)
        local out, n = {}, 0
        local events = file_scope_events(file).items

        local scopes = {}
        local global_declared = {}
        local seen_undef = {}

        local function current_scope()
            return scopes[#scopes]
        end

        local function push_scope(kind)
            scopes[#scopes + 1] = C.ScopeDiagFrame(kind, {})
        end

        local function find_local_in_frame(frame, name)
            for i = 1, #frame.locals do
                local info = frame.locals[i]
                if info.name == name then return info, i end
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
                local name = info.name
                if info.used == 0 and name ~= "_" and name:sub(1, 1) ~= "_" then
                    local code = (info.decl_kind == "param") and "unused-param" or "unused-local"
                    add_diag(code, code:gsub("-", " ") .. " '" .. tostring(name) .. "'", name, scope.scope, info.anchor)
                end
            end
        end

        local function declare_local(name, kind, anchor)
            local scope = current_scope()
            if not scope then return end

            local existing = find_local_in_frame(scope, name)
            if existing then
                add_diag("redeclare-local", "local '" .. tostring(name) .. "' redeclared in same scope", name, scope.scope, anchor)
                return
            end

            local outer_hit = false
            for i = #scopes - 1, 1, -1 do
                if find_local_in_frame(scopes[i], name) then
                    outer_hit = true
                    break
                end
            end
            if outer_hit then
                add_diag("shadowing-local", "local '" .. tostring(name) .. "' shadows outer local", name, scope.scope, anchor)
            elseif BUILTIN_GLOBALS[name] or contains_name(global_declared, name) then
                add_diag("shadowing-global", "local '" .. tostring(name) .. "' shadows global", name, scope.scope, anchor)
            end

            local locals = {}
            for i = 1, #scope.locals do locals[i] = scope.locals[i] end
            locals[#locals + 1] = C.ScopeLocalState(name, kind, 0, anchor_ref(C, anchor or file))
            scopes[#scopes] = C.ScopeDiagFrame(scope.scope, locals)
        end

        local function mark_ref(name, anchor)
            local info, sidx, lidx = find_local(name)
            if info then
                local next_info = C.ScopeLocalState(info.name, info.decl_kind, info.used + 1, info.anchor)
                scopes[sidx] = replace_local(scopes[sidx], lidx, next_info)
                return
            end
            if BUILTIN_GLOBALS[name] or contains_name(global_declared, name) then
                return
            end
            if not contains_name(seen_undef, name) then
                add_name_unique(seen_undef, name)
                local scope = current_scope()
                add_diag("undefined-global", "undefined global '" .. tostring(name) .. "'", name, scope and scope.scope or "?", anchor)
            end
        end

        for i = 1, #events do
            local e = events[i]
            if e.kind == "ScopeEnter" then
                push_scope(e.scope)
            elseif e.kind == "ScopeExit" then
                pop_scope()
            elseif e.kind == "ScopeDeclLocal" then
                declare_local(e.name, e.decl_kind or "local", e.anchor)
            elseif e.kind == "ScopeDeclGlobal" then
                add_name_unique(global_declared, e.name)
            elseif e.kind == "ScopeWrite" then
                local info = find_local(e.name)
                if not info then
                    add_name_unique(global_declared, e.name)
                end
            elseif e.kind == "ScopeRef" then
                mark_ref(e.name, e.anchor)
            end
        end

        return C.DiagnosticSet(out)
    end)

    local symbol_index = pvm.lower("symbol_index", function(file)
        local symbols, defs, uses, unresolved = {}, {}, {}, {}

        local events = file_scope_events(file).items
        local scopes = {}
        local scope_seq = 0
        local globals = {}

        local function symbol_by_id(id)
            for i = 1, #symbols do
                if symbols[i].id == id then return symbols[i] end
            end
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

        local function add_unresolved(name, anchor)
            unresolved[#unresolved + 1] = C.Unresolved(name, anchor_ref(C, anchor or file))
        end

        local function push_scope(kind, anchor)
            scope_seq = scope_seq + 1
            local id = kind .. ":" .. tostring(anchor or file) .. ":" .. tostring(scope_seq)
            scopes[#scopes + 1] = C.ScopeSymbolFrame(kind, id, {})
        end

        local function pop_scope()
            scopes[#scopes] = nil
        end

        local function current_scope()
            return scopes[#scopes]
        end

        local function find_local_in_frame(frame, name)
            for i = 1, #frame.locals do
                local b = frame.locals[i]
                if b.name == name then return b.symbol, i end
            end
            return nil, nil
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
                local b = frame.locals[i]
                if b.name == name then
                    locals[#locals + 1] = C.ScopeSymbolBinding(name, sym)
                    replaced = true
                else
                    locals[#locals + 1] = b
                end
            end
            if not replaced then
                locals[#locals + 1] = C.ScopeSymbolBinding(name, sym)
            end
            return C.ScopeSymbolFrame(frame.scope, frame.id, locals)
        end

        local function find_global(name)
            for i = 1, #globals do
                if globals[i].name == name then return globals[i] end
            end
            return nil
        end

        local function ensure_builtin(name)
            local hit = find_global(name)
            if hit then return hit end
            local sym = add_symbol("builtin:" .. name, "builtin", name, "file", "file", anchor_ref(C, "builtin:" .. name))
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
            local danchor = anchor_ref(C, anchor or (scope.id .. ":" .. tostring(name)))
            local id = danchor.id
            local sym = add_symbol(id, decl_kind, name, scope.scope, scope.id, danchor)
            scopes[#scopes] = set_local(scope, name, sym)
            add_def(sym, danchor)
            return sym
        end

        local function ref_name(name, anchor)
            local local_sym = find_local(name)
            if local_sym then add_use(local_sym, anchor); return end
            local global_sym = find_global(name)
            if global_sym then add_use(global_sym, anchor); return end
            if BUILTIN_GLOBALS[name] then add_use(ensure_builtin(name), anchor); return end
            add_unresolved(name, anchor)
        end

        local function write_name(name, anchor)
            local local_sym = find_local(name)
            if local_sym then add_use(local_sym, anchor) else ensure_global(name, anchor) end
        end

        for i = 1, #events do
            local e = events[i]
            if e.kind == "ScopeEnter" then
                push_scope(e.scope, e.anchor)
            elseif e.kind == "ScopeExit" then
                pop_scope()
            elseif e.kind == "ScopeDeclLocal" then
                declare_local(e.name, e.decl_kind or "local", e.anchor)
            elseif e.kind == "ScopeDeclGlobal" then
                ensure_global(e.name, e.anchor)
            elseif e.kind == "ScopeRef" then
                ref_name(e.name, e.anchor)
            elseif e.kind == "ScopeWrite" then
                write_name(e.name, e.anchor)
            end
        end

        return C.SymbolIndex(symbols, defs, uses, unresolved)
    end)

    local diagnostics = pvm.lower("diagnostics", function(file)
        local out, n = {}, 0

        local function add(d)
            n = n + 1
            out[n] = d
        end

        -- scope-related diagnostics
        local sdiags = scope_diagnostics(file).items
        for i = 1, #sdiags do add(sdiags[i]) end

        -- unknown named types from docs
        local env = resolve_named_types(file)
        local known = {}
        for k in pairs(BUILTIN_TYPES) do add_name_unique(known, k) end
        for i = 1, #env.aliases do add_name_unique(known, env.aliases[i].name) end
        for i = 1, #env.classes do add_name_unique(known, env.classes[i].name) end
        for i = 1, #env.generics do add_name_unique(known, env.generics[i].name) end

        local seen_unknown = {}
        local function emit_unknown(type_name, owner, anchor)
            if contains_name(known, type_name) or contains_name(seen_unknown, type_name) then return end
            add_name_unique(seen_unknown, type_name)
            add(C.Diagnostic(
                "unknown-type",
                "unknown type '" .. tostring(type_name) .. "' in " .. owner,
                type_name,
                "type",
                anchor
            ))
        end

        for i = 1, #env.classes do
            local cls = env.classes[i]
            local cname = cls.name
            for j = 1, #cls.extends do
                local refs = {}
                add_named_type_refs(cls.extends[j], refs)
                for r = 1, #refs do
                    emit_unknown(refs[r], "class " .. cname .. " extends", cls.anchor)
                end
            end
            for j = 1, #cls.fields do
                local f = cls.fields[j]
                local refs = {}
                add_named_type_refs(f.typ, refs)
                for r = 1, #refs do
                    emit_unknown(refs[r], "field " .. cname .. "." .. f.name, f.anchor)
                end
            end
        end

        for i = 1, #env.aliases do
            local alias_def = env.aliases[i]
            local refs = {}
            add_named_type_refs(alias_def.typ, refs)
            for r = 1, #refs do
                emit_unknown(refs[r], "alias " .. alias_def.name, alias_def.anchor)
            end
        end

        return C.DiagnosticSet(out)
    end)

    local function symbol_by_id(idx, symbol_id)
        for i = 1, #idx.symbols do
            if idx.symbols[i].id == symbol_id then return idx.symbols[i] end
        end
        return nil
    end

    local function type_target_kind(tt)
        if tt.kind == "TypeClassTarget" then return "class" end
        if tt.kind == "TypeAliasTarget" then return "alias" end
        if tt.kind == "TypeGenericTarget" then return "generic" end
        if tt.kind == "TypeBuiltinTarget" then return "builtin-type" end
        return "unknown"
    end

    local function query_subject(v)
        if not v then return C.QueryMissing() end
        if type(v) == "table" and v.kind == "TNamed" then
            return C.QueryTypeName(v.name)
        end
        if type(v) == "string" then
            return C.QueryTypeName(v)
        end
        return C.QueryAnchor(anchor_ref(C, v))
    end

    local definitions_of = pvm.lower("definitions_of", function(q)
        local idx = symbol_index(q.file)
        local out = {}
        for i = 1, #idx.defs do
            local d = idx.defs[i]
            if d.symbol_id == q.symbol_id then out[#out + 1] = d end
        end
        return C.OccurrenceList(out)
    end)

    local references_of = pvm.lower("references_of", function(q)
        local idx = symbol_index(q.file)
        local out = {}
        for i = 1, #idx.uses do
            local u = idx.uses[i]
            if u.symbol_id == q.symbol_id then out[#out + 1] = u end
        end
        return C.OccurrenceList(out)
    end)

    local symbol_for_anchor = pvm.lower("symbol_for_anchor", function(q)
        if not q.subject or q.subject.kind ~= "QueryAnchor" then return C.AnchorMissing() end

        local target = q.subject.anchor
        local idx = symbol_index(q.file)

        for i = 1, #idx.defs do
            local d = idx.defs[i]
            if d.anchor == target then
                local sym = symbol_by_id(idx, d.symbol_id)
                if sym then return C.AnchorSymbol(sym, "def") end
            end
        end
        for i = 1, #idx.uses do
            local u = idx.uses[i]
            if u.anchor == target then
                local sym = symbol_by_id(idx, u.symbol_id)
                if sym then return C.AnchorSymbol(sym, "use") end
            end
        end
        for i = 1, #idx.unresolved do
            local u = idx.unresolved[i]
            if u.anchor == target then
                return C.AnchorUnresolved(u.name)
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
            local alias = env.aliases[i]
            if alias.name == q.name then return C.TypeAliasTarget(q.name, alias.anchor, alias) end
        end
        for i = 1, #env.generics do
            local generic = env.generics[i]
            if generic.name == q.name then return C.TypeGenericTarget(q.name, generic.anchor, generic) end
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
            if tt.kind ~= "TypeTargetMissing" then
                return C.DefMiss(C.DefMetaType(tt))
            end
            return C.DefMiss(C.DefMetaMissing())
        end

        local binding = symbol_for_anchor(C.SubjectQuery(q.file, q.subject))
        if binding.kind == "AnchorSymbol" then
            local defs = definitions_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            if #defs > 0 then
                return C.DefHit(defs[1].anchor, C.DefMetaSymbol(binding.role, binding.symbol, defs))
            end
            return C.DefMiss(C.DefMetaSymbol(binding.role, binding.symbol, defs))
        end

        if binding.kind == "AnchorUnresolved" then
            return C.DefMiss(C.DefMetaUnresolved(binding.name))
        end

        return C.DefMiss(C.DefMetaMissing())
    end)

    local find_references = pvm.lower("find_references", function(q)
        local refs = {}
        if not q.subject or q.subject.kind == "QueryMissing" then
            return C.ReferenceResult(refs)
        end

        if q.subject.kind == "QueryTypeName" then
            local tt = type_target(C.TypeNameQuery(q.file, q.subject.name))
            if q.include_declaration and tt.kind ~= "TypeTargetMissing" and tt.anchor then
                local k = type_target_kind(tt)
                refs[#refs + 1] = C.Occurrence("type:" .. k .. ":" .. tt.name, tt.name, k, tt.anchor)
            end
            return C.ReferenceResult(refs)
        end

        local binding = symbol_for_anchor(C.SubjectQuery(q.file, q.subject))
        if binding.kind ~= "AnchorSymbol" then return C.ReferenceResult(refs) end

        if q.include_declaration then
            local defs = definitions_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            for i = 1, #defs do refs[#refs + 1] = defs[i] end
        end

        local uses = references_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
        for i = 1, #uses do refs[#refs + 1] = uses[i] end

        return C.ReferenceResult(refs)
    end)

    local hover = pvm.lower("hover", function(q)
        if not q.subject or q.subject.kind == "QueryMissing" then return C.HoverMissing() end

        if q.subject.kind == "QueryTypeName" then
            local tt = type_target(C.TypeNameQuery(q.file, q.subject.name))
            if tt.kind == "TypeTargetMissing" then
                return C.HoverType(q.subject.name, "unknown type", 0)
            end
            if tt.kind == "TypeClassTarget" then
                return C.HoverType(tt.name, "class", #tt.value.fields)
            elseif tt.kind == "TypeAliasTarget" then
                return C.HoverType(tt.name, "alias", 0)
            elseif tt.kind == "TypeGenericTarget" then
                return C.HoverType(tt.name, "generic", 0)
            end
            return C.HoverType(tt.name, type_target_kind(tt), 0)
        end

        local binding = symbol_for_anchor(C.SubjectQuery(q.file, q.subject))
        if binding.kind == "AnchorSymbol" then
            local n_defs = #definitions_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            local n_uses = #references_of(C.SymbolIdQuery(q.file, binding.symbol.id)).items
            local sym = binding.symbol
            return C.HoverSymbol(binding.role, sym.name, sym.kind, sym.scope, n_defs, n_uses)
        end

        if binding.kind == "AnchorUnresolved" then
            return C.HoverUnresolved(binding.name, "undefined global")
        end

        return C.HoverMissing()
    end)

    local engine = {
        context = ctx,
        C = C,
        bind_symbols = bind_symbols,
        collect_doc_types = collect_doc_types,
        scope_events = scope_events,
        item_scope_summary = item_scope_summary,
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
            self.bind_symbols,
            self.collect_doc_types,
            self.scope_events,
            self.item_scope_summary,
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

    function engine:index(file)
        return symbol_index(file)
    end

    function engine:definitions_of(file, symbol_id)
        return definitions_of(C.SymbolIdQuery(file, symbol_id))
    end

    function engine:references_of(file, symbol_id)
        return references_of(C.SymbolIdQuery(file, symbol_id))
    end

    function engine:symbol_for_anchor(file, anchor)
        return symbol_for_anchor(C.SubjectQuery(file, C.QueryAnchor(anchor_ref(C, anchor))))
    end

    function engine:type_target(file, type_name)
        return type_target(C.TypeNameQuery(file, type_name))
    end

    function engine:goto_definition(file, anchor_or_type)
        return goto_definition(C.SubjectQuery(file, query_subject(anchor_or_type)))
    end

    function engine:find_references(file, anchor_or_type, include_declaration)
        return find_references(C.RefQuery(file, query_subject(anchor_or_type), include_declaration and true or false))
    end

    function engine:hover(file, anchor_or_type)
        return hover(C.SubjectQuery(file, query_subject(anchor_or_type)))
    end

    function engine:reset()
        bind_symbols:reset()
        collect_doc_types:reset()
        scope_events:reset()
        item_scope_summary:reset()
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

function M.smoke()
    local engine = M.new()
    local C = engine.C

    local docs = C.DocBlock({
        C.ClassTag("User", {}),
        C.FieldTag("id", C.TNumber(), false),
        C.FieldTag("name", C.TString(), false),
        C.AliasTag("UserId", C.TNumber()),
    })

    local items = {
        C.Item({ docs }, C.LocalAssign({ C.Name("x") }, { C.Number("1") })),
        C.Item({}, C.CallStmt(C.NameRef("print"), { C.NameRef("x"), C.NameRef("y") })),
    }

    local file = C.File("file:///demo.lua", items)

    local symbols = pvm.drain(engine.bind_symbols(file))
    local types = pvm.drain(engine.collect_doc_types(file))
    local index = engine.symbol_index(file)
    local diags = engine.diagnostics(file)

    return {
        file = file,
        symbols = symbols,
        doc_types = types,
        symbol_index = index,
        diagnostics = diags.items,
        report = engine:report_string(),
    }
end

return M
