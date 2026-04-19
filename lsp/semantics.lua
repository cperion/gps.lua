-- lsp/semantics.lua
--
-- Semantic boundaries over ParsedDoc.
--
-- Architectural center:
--   DocBlock:type_decls()       -> TypeDecl*
--   DocBlock:doc_hints()        -> DocHint*
--   Item:item_semantics()       -> ItemSemantics
--   FuncBody:func_semantics()   -> FuncSemantics
--   Item:item_analysis()        -> ItemAnalysis
--   ParsedDoc:file_analysis()   -> FileAnalysis
--
-- Stable semantic cache boundaries intentionally avoid location wrappers.
-- Documentation/type contributions key on DocBlock. Lexical semantic IR keys on
-- Item and FuncBody. Local binding analysis keys on ScopeSemantics and Item.
-- Whole-file products then assemble those stable semantic products.
--
-- Whole-file products are proper cached boundaries too:
--   ParsedDoc:type_env()                 -> TypeEnv
--   ParsedDoc:file_analysis()            -> FileAnalysis
--   ParsedDoc:symbol_index()             -> SymbolIndex
--   ParsedDoc:local_scope_diagnostics()  -> LocalDiagnosticSet
--   ParsedDoc:type_diagnostics()         -> TypeDiagnosticSet
--   ParsedDoc:diagnostics()              -> Diagnostic*

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")

local M = {}

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
    arg = true, bit = true, ffi = true, jit = true,
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

local function anchor_ref(C, v)
    if not v then return nil end
    if type(v) == "table" then
        local tv = tostring(v)
        if tv:match("^Lua%.AnchorRef%(") then return v end
    end
    return C.AnchorRef(tostring(v))
end

local function append_all(out, xs)
    for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end
end

local function add_name_unique(names, name)
    for i = 1, #names do
        if names[i] == name then return end
    end
    names[#names + 1] = name
end

local function add_named_type_refs(typ, out)
    if not typ then return end
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
    if k == "TFunc" and typ.sig then
        for i = 1, #typ.sig.params do add_named_type_refs(typ.sig.params[i], out) end
        for i = 1, #typ.sig.returns do add_named_type_refs(typ.sig.returns[i], out) end
        return
    end
    if k == "TTable" then
        for i = 1, #typ.fields do add_named_type_refs(typ.fields[i].typ, out) end
        return
    end
end

function M.new(ctx)
    ctx = ctx or ASDL.context()
    local C = ctx.Lua

    local item_semantics_phase
    local func_semantics_phase
    local scope_analysis_phase
    local item_analysis_phase
    local file_analysis_phase

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

    local function query_subject(v)
        if not v then return C.QueryMissing end
        if type(v) == "table" and v.kind == "TNamed" then return C.QueryTypeName(v.name) end
        if type(v) == "string" then return C.QueryTypeName(v) end
        return C.QueryAnchor(anchor_ref(C, v))
    end

    local function each_docblock(item, fn)
        local docs = item.docs or {}
        for i = 1, #docs do fn(docs[i]) end
    end

    local function should_report_unused(name, decl_kind)
        if not name or name == "_" then return false end
        if name:sub(1, 1) == "_" then return false end
        if decl_kind == C.DeclParam and name == "self" then return false end
        return true
    end

    local function issue_to_diagnostic(issue, scope_kind)
        local k = issue.kind
        if k == "IssueRedeclareLocal" then
            return C.Diagnostic(C.DiagRedeclareLocal, "local '" .. issue.name .. "' redeclared in same scope", issue.name, scope_kind, issue.anchor)
        end
        if k == "IssueShadowingLocal" then
            return C.Diagnostic(C.DiagShadowingLocal, "local '" .. issue.name .. "' shadows outer local", issue.name, scope_kind, issue.anchor)
        end
        if k == "IssueShadowingGlobal" then
            return C.Diagnostic(C.DiagShadowingGlobal, "local '" .. issue.name .. "' shadows global", issue.name, scope_kind, issue.anchor)
        end
        local code = (issue.decl_kind == C.DeclParam) and C.DiagUnusedParam or C.DiagUnusedLocal
        local cname = diag_code_name(code)
        return C.Diagnostic(code, cname:gsub("-", " ") .. " '" .. issue.name .. "'", issue.name, scope_kind, issue.anchor)
    end

    -- ── DocBlock -> TypeDecl* ─────────────────────────────

    local type_decls = pvm.phase("type_decls", {
        [C.DocBlock] = function(docblock)
            local decls = {}
            local current_class = nil
            local current_extends = nil
            local current_anchor = nil
            local current_fields = nil

            local function flush_class()
                if current_class then
                    decls[#decls + 1] = C.TypeClassDecl(current_class, current_extends or {}, current_fields or {}, current_anchor)
                    current_class, current_extends, current_anchor, current_fields = nil, nil, nil, nil
                end
            end

            local tags = docblock.tags or {}
            for i = 1, #tags do
                local tag = tags[i]
                local k = tag.kind
                if k == "ClassTag" then
                    flush_class()
                    current_class = tag.name
                    current_extends = tag.extends or {}
                    current_anchor = anchor_ref(C, tag)
                    current_fields = {}
                elseif k == "FieldTag" and current_class then
                    current_fields[#current_fields + 1] = C.TypeClassField(tag.name, tag.typ, tag.optional, anchor_ref(C, tag))
                else
                    flush_class()
                    if k == "AliasTag" then
                        decls[#decls + 1] = C.TypeAliasDecl(tag.name, tag.typ, anchor_ref(C, tag))
                    elseif k == "GenericTag" then
                        decls[#decls + 1] = C.TypeGenericDecl(tag.name, tag.bounds or {}, anchor_ref(C, tag))
                    end
                end
            end
            flush_class()
            return pvm.seq(decls)
        end,
    })

    -- ── DocBlock -> DocHint* ──────────────────────────────

    local doc_hints = pvm.phase("doc_hints", {
        [C.DocBlock] = function(docblock)
            local hints = {}
            local tags = docblock.tags or {}
            for i = 1, #tags do
                local tag = tags[i]
                local k = tag.kind
                if k == "ParamTag" then
                    hints[#hints + 1] = C.HintParam(tag.name, tag.typ, anchor_ref(C, tag))
                elseif k == "ReturnTag" then
                    hints[#hints + 1] = C.HintReturn(tag.values, anchor_ref(C, tag))
                elseif k == "TypeTag" then
                    hints[#hints + 1] = C.HintType(tag.typ, anchor_ref(C, tag))
                elseif k == "OverloadTag" then
                    hints[#hints + 1] = C.HintOverload(tag.sig, anchor_ref(C, tag))
                elseif k == "CastTag" then
                    hints[#hints + 1] = C.HintCast(tag.typ, anchor_ref(C, tag))
                elseif k == "MetaTag" then
                    hints[#hints + 1] = C.HintMeta(tag.name, tag.text, anchor_ref(C, tag))
                end
            end
            return pvm.seq(hints)
        end,
    })

    -- ── Item / FuncBody -> lexical semantic IR ────────────────────

    local function add_op_access(ops, kind, name, anchor)
        ops[#ops + 1] = C.OpAccess(kind, name, anchor_ref(C, anchor))
    end

    local function add_op_decl_local(ops, decl_kind, name, anchor)
        ops[#ops + 1] = C.OpDeclLocal(decl_kind, name, anchor_ref(C, anchor))
    end

    local function add_op_decl_global(ops, name, anchor)
        ops[#ops + 1] = C.OpDeclGlobal(name, anchor_ref(C, anchor))
    end

    local function add_op_child_scope(ops, scope)
        ops[#ops + 1] = C.OpChildScope(scope)
    end

    local build_ops_from_stmt, build_ops_from_expr, build_ops_from_block, build_ops_from_lvalue

    build_ops_from_lvalue = function(lv, ops)
        if not lv then return end
        local k = lv.kind
        if k == "LField" then
            build_ops_from_expr(lv.base, ops)
        elseif k == "LIndex" then
            build_ops_from_expr(lv.base, ops)
            build_ops_from_expr(lv.key, ops)
        elseif k == "LMethod" then
            build_ops_from_expr(lv.base, ops)
        end
    end

    build_ops_from_expr = function(expr, ops)
        if not expr then return end
        local k = expr.kind
        if k == "NameRef" then
            add_op_access(ops, C.AccessRead, expr.name, expr)
            return
        end
        if k == "Field" then
            build_ops_from_expr(expr.base, ops)
            return
        end
        if k == "Index" then
            build_ops_from_expr(expr.base, ops)
            build_ops_from_expr(expr.key, ops)
            return
        end
        if k == "Call" then
            build_ops_from_expr(expr.callee, ops)
            for i = 1, #expr.args do build_ops_from_expr(expr.args[i], ops) end
            return
        end
        if k == "MethodCall" then
            build_ops_from_expr(expr.recv, ops)
            for i = 1, #expr.args do build_ops_from_expr(expr.args[i], ops) end
            return
        end
        if k == "FunctionExpr" then
            add_op_child_scope(ops, pvm.one(func_semantics_phase(expr.body)).scope)
            return
        end
        if k == "TableCtor" then
            for i = 1, #expr.fields do
                local f = expr.fields[i]
                if f.kind == "ArrayField" then
                    build_ops_from_expr(f.value, ops)
                elseif f.kind == "PairField" then
                    build_ops_from_expr(f.key, ops)
                    build_ops_from_expr(f.value, ops)
                elseif f.kind == "NameField" then
                    build_ops_from_expr(f.value, ops)
                end
            end
            return
        end
        if k == "Unary" then
            build_ops_from_expr(expr.value, ops)
            return
        end
        if k == "Binary" then
            build_ops_from_expr(expr.lhs, ops)
            build_ops_from_expr(expr.rhs, ops)
            return
        end
        if k == "Paren" then
            build_ops_from_expr(expr.inner, ops)
            return
        end
    end

    build_ops_from_block = function(block, ops)
        if not block then return end
        for i = 1, #(block.items or {}) do
            build_ops_from_stmt(block.items[i].stmt, ops)
        end
    end

    local function build_scope_semantics(kind, anchor, fill)
        local ops = {}
        fill(ops)
        return C.ScopeSemantics(kind, anchor_ref(C, anchor), ops)
    end

    build_ops_from_stmt = function(stmt, ops)
        if not stmt then return end
        local k = stmt.kind

        if k == "LocalAssign" then
            for i = 1, #stmt.values do build_ops_from_expr(stmt.values[i], ops) end
            for i = 1, #stmt.names do add_op_decl_local(ops, C.DeclLocal, stmt.names[i].value, stmt.names[i]) end
            return
        end

        if k == "Assign" then
            for i = 1, #stmt.rhs do build_ops_from_expr(stmt.rhs[i], ops) end
            for i = 1, #stmt.lhs do
                build_ops_from_lvalue(stmt.lhs[i], ops)
                if stmt.lhs[i].kind == "LName" then
                    add_op_access(ops, C.AccessWrite, stmt.lhs[i].name, stmt.lhs[i])
                end
            end
            return
        end

        if k == "LocalFunction" then
            add_op_decl_local(ops, C.DeclLocal, stmt.name, stmt)
            add_op_child_scope(ops, pvm.one(func_semantics_phase(stmt.body)).scope)
            return
        end

        if k == "Function" then
            if stmt.name and stmt.name.kind == "LName" then
                add_op_decl_global(ops, stmt.name.name, stmt.name)
            else
                build_ops_from_lvalue(stmt.name, ops)
            end
            add_op_child_scope(ops, pvm.one(func_semantics_phase(stmt.body)).scope)
            return
        end

        if k == "Return" then
            for i = 1, #stmt.values do build_ops_from_expr(stmt.values[i], ops) end
            return
        end

        if k == "CallStmt" then
            build_ops_from_expr(stmt.callee, ops)
            for i = 1, #stmt.args do build_ops_from_expr(stmt.args[i], ops) end
            return
        end

        if k == "If" then
            for i = 1, #stmt.arms do
                local arm = stmt.arms[i]
                build_ops_from_expr(arm.cond, ops)
                add_op_child_scope(ops, build_scope_semantics(C.ScopeIf, arm, function(child_ops)
                    build_ops_from_block(arm.body, child_ops)
                end))
            end
            if stmt.else_block and #stmt.else_block.items > 0 then
                add_op_child_scope(ops, build_scope_semantics(C.ScopeElse, stmt.else_block, function(child_ops)
                    build_ops_from_block(stmt.else_block, child_ops)
                end))
            end
            return
        end

        if k == "While" then
            build_ops_from_expr(stmt.cond, ops)
            add_op_child_scope(ops, build_scope_semantics(C.ScopeWhile, stmt, function(child_ops)
                build_ops_from_block(stmt.body, child_ops)
            end))
            return
        end

        if k == "Repeat" then
            add_op_child_scope(ops, build_scope_semantics(C.ScopeRepeat, stmt, function(child_ops)
                build_ops_from_block(stmt.body, child_ops)
                build_ops_from_expr(stmt.cond, child_ops)
            end))
            return
        end

        if k == "ForNum" then
            build_ops_from_expr(stmt.init, ops)
            build_ops_from_expr(stmt.limit, ops)
            build_ops_from_expr(stmt.step, ops)
            add_op_child_scope(ops, build_scope_semantics(C.ScopeFor, stmt, function(child_ops)
                add_op_decl_local(child_ops, C.DeclLocal, stmt.name, stmt)
                build_ops_from_block(stmt.body, child_ops)
            end))
            return
        end

        if k == "ForIn" then
            for i = 1, #stmt.iter do build_ops_from_expr(stmt.iter[i], ops) end
            add_op_child_scope(ops, build_scope_semantics(C.ScopeFor, stmt, function(child_ops)
                for i = 1, #stmt.names do add_op_decl_local(child_ops, C.DeclLocal, stmt.names[i].value, stmt.names[i]) end
                build_ops_from_block(stmt.body, child_ops)
            end))
            return
        end

        if k == "Do" then
            add_op_child_scope(ops, build_scope_semantics(C.ScopeDo, stmt, function(child_ops)
                build_ops_from_block(stmt.body, child_ops)
            end))
            return
        end
    end

    item_semantics_phase = pvm.phase("item_semantics", function(item)
        local ops = {}
        build_ops_from_stmt(item.stmt, ops)
        return C.ItemSemantics(ops)
    end)

    func_semantics_phase = pvm.phase("func_semantics", function(body)
        local scope = build_scope_semantics(C.ScopeFunction, body, function(ops)
            for i = 1, #body.params do add_op_decl_local(ops, C.DeclParam, body.params[i].name, body.params[i]) end
            build_ops_from_block(body.body, ops)
        end)
        return C.FuncSemantics(scope)
    end)

    -- ── ScopeSemantics / Item -> analyzed semantic summaries ───────

    local function analyze_named_ops(kind, scope_anchor, ops, opts)
        opts = opts or {}
        local binding_infos = {}
        local current_locals = {}
        local globals = {}
        local global_uses = {}
        local free_uses = {}
        local issues = {}
        local children = {}
        local globals_seen = {}

        local function add_issue(v)
            issues[#issues + 1] = v
        end

        local function new_binding(decl_kind, name, decl_anchor)
            local info = {
                decl_kind = decl_kind,
                name = name,
                decl_anchor = anchor_ref(C, decl_anchor),
                uses = {},
            }
            binding_infos[#binding_infos + 1] = info
            current_locals[name] = info
            return info
        end

        local function add_binding_use(info, access_kind, use_anchor)
            info.uses[#info.uses + 1] = C.BindingUse(access_kind, anchor_ref(C, use_anchor))
        end

        local function note_unresolved(access_kind, name, use_anchor, use_scope)
            free_uses[#free_uses + 1] = C.FreeUse(access_kind, name, anchor_ref(C, use_anchor), use_scope)
            if access_kind == C.AccessWrite then
                globals_seen[name] = true
            end
        end

        local function process_free_use(free)
            local hit = current_locals[free.name]
            if hit then
                add_binding_use(hit, free.kind, free.anchor)
            elseif globals_seen[free.name] then
                global_uses[#global_uses + 1] = C.GlobalUse(free.kind, free.name, free.anchor)
            else
                note_unresolved(free.kind, free.name, free.anchor, free.scope)
            end
        end

        for i = 1, #ops do
            local op = ops[i]
            local ok = op.kind
            if ok == "OpDeclLocal" then
                if opts.emit_redeclare and current_locals[op.name] then
                    add_issue(C.IssueRedeclareLocal(op.name, op.anchor))
                end
                if opts.emit_builtin_shadow and BUILTIN_GLOBALS[op.name] then
                    add_issue(C.IssueShadowingGlobal(op.name, op.anchor))
                end
                new_binding(op.decl_kind, op.name, op.anchor)
            elseif ok == "OpDeclGlobal" then
                globals[#globals + 1] = C.GlobalDecl(op.name, op.anchor)
                globals_seen[op.name] = true
            elseif ok == "OpAccess" then
                local hit = current_locals[op.name]
                if hit then
                    add_binding_use(hit, op.access_kind, op.anchor)
                elseif globals_seen[op.name] then
                    global_uses[#global_uses + 1] = C.GlobalUse(op.access_kind, op.name, op.anchor)
                else
                    note_unresolved(op.access_kind, op.name, op.anchor, kind)
                end
            elseif ok == "OpChildScope" then
                local child = pvm.one(scope_analysis_phase(op.scope))
                children[#children + 1] = child
                append_all(global_uses, child.global_uses)
                for j = 1, #child.globals do
                    globals[#globals + 1] = child.globals[j]
                    globals_seen[child.globals[j].name] = true
                end
                for j = 1, #child.free_uses do process_free_use(child.free_uses[j]) end
            end
        end

        if opts.emit_unused then
            for i = 1, #binding_infos do
                local info = binding_infos[i]
                if #info.uses == 0 and should_report_unused(info.name, info.decl_kind) then
                    add_issue(C.IssueUnused(info.decl_kind, info.name, info.decl_anchor))
                end
            end
        end

        local bindings = {}
        for i = 1, #binding_infos do
            local info = binding_infos[i]
            bindings[i] = C.LocalBinding(info.decl_kind, info.name, info.decl_anchor, info.uses)
        end

        return bindings, globals, global_uses, free_uses, issues, children
    end

    scope_analysis_phase = pvm.phase("scope_analysis", function(scope)
        local bindings, globals, global_uses, free_uses, issues, children = analyze_named_ops(
            scope.kind,
            scope.anchor,
            scope.ops or {},
            { emit_redeclare = true, emit_builtin_shadow = true, emit_unused = true }
        )
        return C.ScopeAnalysis(scope.kind, scope.anchor, bindings, globals, global_uses, free_uses, issues, children)
    end)

    item_analysis_phase = pvm.phase("item_analysis", function(item)
        local sem = pvm.one(item_semantics_phase(item))
        local bindings, globals, global_uses, free_uses, issues, children = analyze_named_ops(
            C.ScopeFile,
            anchor_ref(C, item),
            sem.ops or {},
            { emit_redeclare = false, emit_builtin_shadow = false, emit_unused = false }
        )
        return C.ItemAnalysis(bindings, globals, global_uses, free_uses, issues, children)
    end)

    local function copy_binding(binding)
        local uses = {}
        for i = 1, #binding.uses do uses[i] = binding.uses[i] end
        return {
            decl_kind = binding.decl_kind,
            name = binding.name,
            decl_anchor = binding.decl_anchor,
            uses = uses,
        }
    end

    file_analysis_phase = pvm.phase("file_analysis", function(doc)
        local items = {}
        local file_binding_infos = {}
        local current_file_locals = {}
        local globals = {}
        local global_uses = {}
        local unresolved_uses = {}
        local issues = {}
        local current_globals = {}

        for i = 1, #doc.items do
            local item = pvm.one(item_analysis_phase(doc.items[i].core))
            items[i] = item

            for j = 1, #item.free_uses do
                local free = item.free_uses[j]
                local hit = current_file_locals[free.name]
                if hit then
                    hit.uses[#hit.uses + 1] = C.BindingUse(free.kind, free.anchor)
                elseif current_globals[free.name] then
                    global_uses[#global_uses + 1] = C.GlobalUse(free.kind, free.name, free.anchor)
                else
                    unresolved_uses[#unresolved_uses + 1] = free
                    if free.kind == C.AccessWrite then current_globals[free.name] = true end
                end
            end

            append_all(global_uses, item.global_uses)
            for j = 1, #item.globals do
                globals[#globals + 1] = item.globals[j]
                current_globals[item.globals[j].name] = true
            end

            for j = 1, #item.bindings do
                local b = item.bindings[j]
                if current_file_locals[b.name] then
                    issues[#issues + 1] = C.IssueRedeclareLocal(b.name, b.decl_anchor)
                elseif BUILTIN_GLOBALS[b.name] then
                    issues[#issues + 1] = C.IssueShadowingGlobal(b.name, b.decl_anchor)
                end
                local info = copy_binding(b)
                file_binding_infos[#file_binding_infos + 1] = info
                current_file_locals[b.name] = info
            end
        end

        local bindings = {}
        for i = 1, #file_binding_infos do
            local info = file_binding_infos[i]
            if #info.uses == 0 and should_report_unused(info.name, info.decl_kind) then
                issues[#issues + 1] = C.IssueUnused(info.decl_kind, info.name, info.decl_anchor)
            end
            bindings[i] = C.LocalBinding(info.decl_kind, info.name, info.decl_anchor, info.uses)
        end

        return C.FileAnalysis(items, bindings, globals, global_uses, unresolved_uses, issues)
    end)

    -- ── ParsedDoc -> TypeEnv ──────────────────────────────

    local type_env_phase = pvm.phase("type_env", function(doc)
        local classes, aliases, generics = {}, {}, {}

        local function class_index(name)
            for i = 1, #classes do if classes[i].name == name then return i end end
            return nil
        end
        local function alias_index(name)
            for i = 1, #aliases do if aliases[i].name == name then return i end end
            return nil
        end
        local function generic_index(name)
            for i = 1, #generics do if generics[i].name == name then return i end end
            return nil
        end

        for i = 1, #doc.items do
            each_docblock(doc.items[i].core, function(db)
                for _, d in type_decls(db) do
                    if d.kind == "TypeClassDecl" then
                        local cls = C.TypeClass(d.name, d.extends, d.fields, d.anchor)
                        local idx = class_index(d.name)
                        if idx then classes[idx] = cls else classes[#classes + 1] = cls end
                    elseif d.kind == "TypeAliasDecl" then
                        local a = C.TypeAlias(d.name, d.typ, d.anchor)
                        local idx = alias_index(d.name)
                        if idx then aliases[idx] = a else aliases[#aliases + 1] = a end
                    elseif d.kind == "TypeGenericDecl" then
                        local g = C.TypeGeneric(d.name, d.bounds, d.anchor)
                        local idx = generic_index(d.name)
                        if idx then generics[idx] = g else generics[#generics + 1] = g end
                    end
                end
            end)
        end

        return C.TypeEnv(classes, aliases, generics)
    end)

    -- ── ParsedDoc -> SymbolIndex ──────────────────────────

    local symbol_index_phase = pvm.phase("symbol_index", function(doc)
        local env = pvm.one(type_env_phase(doc))
        local fa = pvm.one(file_analysis_phase(doc))
        local symbols, defs, uses, unresolved = {}, {}, {}, {}
        local globals = {}

        local function symbol_by_id(id)
            for i = 1, #symbols do if symbols[i].id == id then return symbols[i] end end
            return nil
        end

        local function add_symbol(id, kind, name, scope, scope_id, decl_anchor)
            local hit = symbol_by_id(id)
            if hit then return hit end
            local sym = C.Symbol(id, kind, name, scope, scope_id, decl_anchor)
            symbols[#symbols + 1] = sym
            return sym
        end

        local function add_def(sym, anchor)
            defs[#defs + 1] = C.Occurrence(sym.id, sym.name, sym.kind, anchor_ref(C, anchor))
        end

        local function add_use(sym, anchor)
            uses[#uses + 1] = C.Occurrence(sym.id, sym.name, sym.kind, anchor_ref(C, anchor))
        end

        local function ensure_builtin(name)
            local hit = globals[name]
            if hit and hit.kind == C.SymBuiltin then return hit end
            local sym = add_symbol("builtin:" .. name, C.SymBuiltin, name, C.ScopeFile, "file", anchor_ref(C, "builtin:" .. name))
            globals[name] = sym
            return sym
        end

        local function ensure_global(name, anchor)
            local hit = globals[name]
            if hit and hit.kind == C.SymGlobal then return hit end
            local danchor = anchor_ref(C, anchor or ("global:" .. name))
            local sym = add_symbol("global:" .. name, C.SymGlobal, name, C.ScopeFile, "file", danchor)
            globals[name] = sym
            return sym
        end

        local function add_type_symbols()
            for i = 1, #env.classes do
                local v = env.classes[i]
                local sym = add_symbol("typeclass:" .. v.name, C.SymTypeClass, v.name, C.ScopeType, "type", v.anchor)
                add_def(sym, v.anchor)
            end
            for i = 1, #env.aliases do
                local v = env.aliases[i]
                local sym = add_symbol("typealias:" .. v.name, C.SymTypeAlias, v.name, C.ScopeType, "type", v.anchor)
                add_def(sym, v.anchor)
            end
            for i = 1, #env.generics do
                local v = env.generics[i]
                local sym = add_symbol("typegeneric:" .. v.name, C.SymTypeGeneric, v.name, C.ScopeType, "type", v.anchor)
                add_def(sym, v.anchor)
            end
        end

        local function walk_bindings(bindings, scope_kind, scope_id)
            for i = 1, #bindings do
                local b = bindings[i]
                local sym = add_symbol(b.decl_anchor.id, symbol_kind_from_decl(b.decl_kind), b.name, scope_kind, scope_id, b.decl_anchor)
                add_def(sym, b.decl_anchor)
                for j = 1, #b.uses do add_use(sym, b.uses[j].anchor) end
            end
        end

        local function walk_scope(scope)
            local sid = scope_kind_name(scope.kind) .. ":" .. tostring(scope.anchor and scope.anchor.id or "")
            walk_bindings(scope.bindings, scope.kind, sid)
            for i = 1, #scope.children do walk_scope(scope.children[i]) end
        end

        add_type_symbols()
        walk_bindings(fa.bindings, C.ScopeFile, "file")

        for i = 1, #fa.globals do
            local g = fa.globals[i]
            add_def(ensure_global(g.name, g.anchor), g.anchor)
        end
        for i = 1, #fa.global_uses do
            local g = fa.global_uses[i]
            add_use(ensure_global(g.name, g.anchor), g.anchor)
        end
        for i = 1, #fa.unresolved_uses do
            local u = fa.unresolved_uses[i]
            if u.kind == C.AccessWrite then
                local sym = ensure_global(u.name, u.anchor)
                add_def(sym, u.anchor)
                add_use(sym, u.anchor)
            elseif BUILTIN_GLOBALS[u.name] then
                add_use(ensure_builtin(u.name), u.anchor)
            else
                unresolved[#unresolved + 1] = C.Unresolved(u.name, u.anchor)
            end
        end

        for i = 1, #fa.items do
            local item = fa.items[i]
            for j = 1, #item.children do walk_scope(item.children[j]) end
        end

        return C.SymbolIndex(symbols, defs, uses, unresolved)
    end)

    -- ── ParsedDoc -> Diagnostic assemblies ───────────────────────

    local local_scope_diagnostics_phase = pvm.phase("local_scope_diagnostics", function(doc)
        local fa = pvm.one(file_analysis_phase(doc))
        local out = {}

        local function add_diag_from_issue(issue, scope_kind)
            out[#out + 1] = issue_to_diagnostic(issue, scope_kind)
        end

        local function walk_scope(scope)
            for i = 1, #scope.issues do add_diag_from_issue(scope.issues[i], scope.kind) end
            for i = 1, #scope.children do walk_scope(scope.children[i]) end
        end

        for i = 1, #fa.issues do add_diag_from_issue(fa.issues[i], C.ScopeFile) end
        for i = 1, #fa.unresolved_uses do
            local u = fa.unresolved_uses[i]
            if not BUILTIN_GLOBALS[u.name] then
                out[#out + 1] = C.Diagnostic(C.DiagUndefinedGlobal, "undefined global '" .. u.name .. "'", u.name, u.scope or C.ScopeFile, u.anchor)
            end
        end
        for i = 1, #fa.items do
            for j = 1, #fa.items[i].issues do add_diag_from_issue(fa.items[i].issues[j], C.ScopeFile) end
            for j = 1, #fa.items[i].children do walk_scope(fa.items[i].children[j]) end
        end

        return C.LocalDiagnosticSet(out)
    end)

    local type_diagnostics_phase = pvm.phase("type_diagnostics", function(doc)
        local env = pvm.one(type_env_phase(doc))
        local out = {}

        local function add_diag(code, message, name, scope_kind, anchor)
            out[#out + 1] = C.Diagnostic(code, message, name or "", scope_kind or C.ScopeFile, anchor_ref(C, anchor or doc))
        end

        local known = {}
        for k in pairs(BUILTIN_TYPES) do known[#known + 1] = k end
        for i = 1, #env.classes do add_name_unique(known, env.classes[i].name) end
        for i = 1, #env.aliases do add_name_unique(known, env.aliases[i].name) end
        for i = 1, #env.generics do add_name_unique(known, env.generics[i].name) end

        local function known_type(name)
            for i = 1, #known do if known[i] == name then return true end end
            return false
        end

        local function check_named_refs(anchor, typ)
            local names = {}
            add_named_type_refs(typ, names)
            for i = 1, #names do
                if not BUILTIN_TYPES[names[i]] and not known_type(names[i]) then
                    add_diag(C.DiagUnknownType, "unknown type '" .. names[i] .. "'", names[i], C.ScopeType, anchor)
                end
            end
        end

        for i = 1, #doc.items do
            each_docblock(doc.items[i].core, function(db)
                for _, d in type_decls(db) do
                    if d.kind == "TypeClassDecl" then
                        for j = 1, #d.extends do check_named_refs(d.anchor, d.extends[j]) end
                        for j = 1, #d.fields do check_named_refs(d.fields[j].anchor, d.fields[j].typ) end
                    elseif d.kind == "TypeAliasDecl" then
                        check_named_refs(d.anchor, d.typ)
                    elseif d.kind == "TypeGenericDecl" then
                        for j = 1, #d.bounds do check_named_refs(d.anchor, d.bounds[j]) end
                    end
                end
                for _, h in doc_hints(db) do
                    if h.kind == "HintParam" or h.kind == "HintType" or h.kind == "HintCast" then
                        check_named_refs(h.anchor, h.typ)
                    elseif h.kind == "HintReturn" then
                        for j = 1, #h.values do check_named_refs(h.anchor, h.values[j]) end
                    elseif h.kind == "HintOverload" and h.sig then
                        for j = 1, #h.sig.params do check_named_refs(h.anchor, h.sig.params[j]) end
                        for j = 1, #h.sig.returns do check_named_refs(h.anchor, h.sig.returns[j]) end
                    end
                end
            end)
        end

        return C.TypeDiagnosticSet(out)
    end)

    local diagnostics_phase = pvm.phase("diagnostics", {
        [C.ParsedDoc] = function(doc)
            local local_diags = pvm.one(local_scope_diagnostics_phase(doc))
            local type_diags = pvm.one(type_diagnostics_phase(doc))
            return pvm.concat_all({
                { pvm.seq(local_diags.items) },
                { pvm.seq(type_diags.items) },
            })
        end,
    })

    -- ── Query phases ───────────────────────────────────────

    local definitions_of = pvm.phase("definitions_of", {
        [C.SymbolIdQuery] = function(q)
            local idx = pvm.one(symbol_index_phase(q.doc))
            local out = {}
            for i = 1, #idx.defs do if idx.defs[i].symbol_id == q.symbol_id then out[#out + 1] = idx.defs[i] end end
            return pvm.seq(out)
        end,
    })

    local references_of = pvm.phase("references_of", {
        [C.SymbolIdQuery] = function(q)
            local idx = pvm.one(symbol_index_phase(q.doc))
            local out = {}
            for i = 1, #idx.uses do if idx.uses[i].symbol_id == q.symbol_id then out[#out + 1] = idx.uses[i] end end
            return pvm.seq(out)
        end,
    })

    local function symbol_by_id(idx, sid)
        for i = 1, #idx.symbols do if idx.symbols[i].id == sid then return idx.symbols[i] end end
        return nil
    end

    local symbol_for_anchor = pvm.phase("symbol_for_anchor", function(q)
        if not q.subject or q.subject.kind ~= "QueryAnchor" then return C.AnchorMissing end
        local target = q.subject.anchor
        local idx = pvm.one(symbol_index_phase(q.doc))

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
            if idx.unresolved[i].anchor == target then return C.AnchorUnresolved(idx.unresolved[i].name) end
        end

        local env = pvm.one(type_env_phase(q.doc))
        for i = 1, #env.classes do if env.classes[i].anchor == target then return C.AnchorTypeName(env.classes[i].name) end end
        for i = 1, #env.aliases do if env.aliases[i].anchor == target then return C.AnchorTypeName(env.aliases[i].name) end end
        for i = 1, #env.generics do if env.generics[i].anchor == target then return C.AnchorTypeName(env.generics[i].name) end end

        return C.AnchorMissing
    end)

    local type_target = pvm.phase("type_target", function(q)
        local env = pvm.one(type_env_phase(q.doc))
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
            if tt.kind ~= "TypeTargetMissing" and tt.anchor then return C.DefHit(tt.anchor, C.DefMetaType(tt)) end
            return C.DefMiss(C.DefMetaMissing)
        end

        local hit = pvm.one(symbol_for_anchor(q))
        if hit.kind == "AnchorTypeName" then
            local tt = pvm.one(type_target(C.TypeNameQuery(q.doc, hit.name)))
            if tt.kind ~= "TypeTargetMissing" and tt.anchor then return C.DefHit(tt.anchor, C.DefMetaType(tt)) end
            return C.DefMiss(C.DefMetaMissing)
        elseif hit.kind == "AnchorSymbol" then
            local defs = pvm.drain(definitions_of(C.SymbolIdQuery(q.doc, hit.symbol.id)))
            if #defs > 0 then return C.DefHit(defs[1].anchor, C.DefMetaSymbol(hit.role, hit.symbol, defs)) end
            return C.DefMiss(C.DefMetaSymbol(hit.role, hit.symbol, defs))
        elseif hit.kind == "AnchorUnresolved" then
            return C.DefMiss(C.DefMetaUnresolved(hit.name))
        end

        return C.DefMiss(C.DefMetaMissing)
    end)

    local find_references = pvm.phase("find_references", {
        [C.RefQuery] = function(q)
            if not q.subject or q.subject.kind ~= "QueryAnchor" then return pvm.empty() end
            local hit = pvm.one(symbol_for_anchor(C.SubjectQuery(q.doc, q.subject)))
            if hit.kind ~= "AnchorSymbol" then return pvm.empty() end

            local refs = pvm.drain(references_of(C.SymbolIdQuery(q.doc, hit.symbol.id)))
            if q.include_declaration then
                local defs = pvm.drain(definitions_of(C.SymbolIdQuery(q.doc, hit.symbol.id)))
                local out = {}
                for i = 1, #defs do out[#out + 1] = defs[i] end
                for i = 1, #refs do out[#out + 1] = refs[i] end
                return pvm.seq(out)
            end
            return pvm.seq(refs)
        end,
    })

    local hover = pvm.phase("hover", function(q)
        if not q.subject or q.subject.kind == "QueryMissing" then return C.HoverMissing end

        local function hover_for_type_name(name)
            local tt = pvm.one(type_target(C.TypeNameQuery(q.doc, name)))
            if tt.kind == "TypeClassTarget" then return C.HoverType(tt.name, "class", #tt.value.fields) end
            if tt.kind == "TypeAliasTarget" then return C.HoverType(tt.name, "alias", 0) end
            if tt.kind == "TypeGenericTarget" then return C.HoverType(tt.name, "generic", 0) end
            if tt.kind == "TypeBuiltinTarget" then return C.HoverType(tt.name, "builtin-type", 0) end
            return C.HoverMissing
        end

        if q.subject.kind == "QueryTypeName" then
            return hover_for_type_name(q.subject.name)
        end

        local hit = pvm.one(symbol_for_anchor(q))
        if hit.kind == "AnchorTypeName" then
            return hover_for_type_name(hit.name)
        elseif hit.kind == "AnchorUnresolved" then
            return C.HoverUnresolved(hit.name, "unresolved")
        elseif hit.kind ~= "AnchorSymbol" then
            return C.HoverMissing
        end

        local defs = pvm.drain(definitions_of(C.SymbolIdQuery(q.doc, hit.symbol.id)))
        local refs = pvm.drain(references_of(C.SymbolIdQuery(q.doc, hit.symbol.id)))
        return C.HoverSymbol(hit.role, hit.symbol.name, hit.symbol.kind, hit.symbol.scope, #defs, #refs, C.TUnknown)
    end)

    -- ── Engine facade ──────────────────────────────────────

    local engine

    local function unwrap1(a, b)
        if a == engine then return b end
        return a
    end
    local function unwrap2(a, b, c)
        if a == engine then return b, c end
        return a, b
    end
    local function unwrap3(a, b, c, d)
        if a == engine then return b, c, d end
        return a, b, c
    end

    engine = {
        C = C,
        context = ctx,

        type_decls_phase = type_decls,
        doc_hints_phase = doc_hints,
        item_semantics_phase = item_semantics_phase,
        func_semantics_phase = func_semantics_phase,
        scope_analysis_phase = scope_analysis_phase,
        item_analysis_phase = item_analysis_phase,
        file_analysis_phase = file_analysis_phase,
        type_env_phase = type_env_phase,
        symbol_index_phase = symbol_index_phase,
        local_scope_diagnostics_phase = local_scope_diagnostics_phase,
        type_diagnostics_phase = type_diagnostics_phase,
        diagnostics_phase = diagnostics_phase,
        definitions_of_phase = definitions_of,
        references_of_phase = references_of,
        symbol_for_anchor_phase = symbol_for_anchor,
        type_target_phase = type_target,
        goto_definition_phase = goto_definition,
        find_references_phase = find_references,
        hover_phase = hover,
    }

    engine.report_string = function()
        return pvm.report_string({
            engine.type_decls_phase,
            engine.doc_hints_phase,
            engine.item_semantics_phase,
            engine.func_semantics_phase,
            engine.scope_analysis_phase,
            engine.item_analysis_phase,
            engine.file_analysis_phase,
            engine.type_env_phase,
            engine.symbol_index_phase,
            engine.local_scope_diagnostics_phase,
            engine.type_diagnostics_phase,
            engine.diagnostics_phase,
            engine.definitions_of_phase,
            engine.references_of_phase,
            engine.symbol_for_anchor_phase,
            engine.type_target_phase,
            engine.goto_definition_phase,
            engine.find_references_phase,
            engine.hover_phase,
        })
    end

    engine.item_semantics = function(a, b)
        local item = unwrap1(a, b)
        return pvm.one(item_semantics_phase(item))
    end

    engine.func_semantics = function(a, b)
        local body = unwrap1(a, b)
        return pvm.one(func_semantics_phase(body))
    end

    engine.scope_analysis = function(a, b)
        local scope = unwrap1(a, b)
        return pvm.one(scope_analysis_phase(scope))
    end

    engine.item_analysis = function(a, b)
        local item = unwrap1(a, b)
        return pvm.one(item_analysis_phase(item))
    end

    engine.file_analysis = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(file_analysis_phase(doc))
    end

    engine.type_env = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(type_env_phase(doc))
    end

    engine.resolve_named_types = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(type_env_phase(doc))
    end

    engine.local_scope_diagnostics = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(local_scope_diagnostics_phase(doc))
    end

    engine.type_diagnostics = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(type_diagnostics_phase(doc))
    end

    engine.diagnostics = function(a, b)
        local doc = unwrap1(a, b)
        return diagnostics_phase(doc)
    end

    engine.index = function(a, b)
        local doc = unwrap1(a, b)
        return pvm.one(symbol_index_phase(doc))
    end

    engine.definitions_of = function(a, b, c)
        local doc, symbol_id = unwrap2(a, b, c)
        return definitions_of(C.SymbolIdQuery(doc, symbol_id))
    end

    engine.references_of = function(a, b, c)
        local doc, symbol_id = unwrap2(a, b, c)
        return references_of(C.SymbolIdQuery(doc, symbol_id))
    end

    engine.symbol_for_anchor = function(a, b, c)
        local doc, anchor = unwrap2(a, b, c)
        return symbol_for_anchor(C.SubjectQuery(doc, C.QueryAnchor(anchor_ref(C, anchor))))
    end

    engine.type_target = function(a, b, c)
        local doc, name = unwrap2(a, b, c)
        return type_target(C.TypeNameQuery(doc, name))
    end

    engine.goto_definition = function(a, b, c)
        local doc, v = unwrap2(a, b, c)
        return goto_definition(C.SubjectQuery(doc, query_subject(v)))
    end

    engine.find_references = function(a, b, c, d)
        local doc, v, include_decl = unwrap3(a, b, c, d)
        return find_references(C.RefQuery(doc, query_subject(v), include_decl and true or false))
    end

    engine.hover = function(a, b, c)
        local doc, v = unwrap2(a, b, c)
        return hover(C.SubjectQuery(doc, query_subject(v)))
    end

    engine.reset = function()
        type_decls:reset()
        doc_hints:reset()
        item_semantics_phase:reset()
        func_semantics_phase:reset()
        scope_analysis_phase:reset()
        item_analysis_phase:reset()
        file_analysis_phase:reset()
        type_env_phase:reset()
        symbol_index_phase:reset()
        local_scope_diagnostics_phase:reset()
        type_diagnostics_phase:reset()
        diagnostics_phase:reset()
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
