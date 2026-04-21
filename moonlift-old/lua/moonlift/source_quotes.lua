return function(ctx)
    local parse_backend_ast = assert(ctx.parse_backend_ast)
    local attach_ast_meta = assert(ctx.attach_ast_meta)
    local clone_ast = assert(ctx.clone_ast)
    local caller_env = assert(ctx.caller_env)
    local source_new_env = assert(ctx.source_new_env)
    local source_child_env = assert(ctx.source_child_env)
    local source_merge_host_bindings = assert(ctx.source_merge_host_bindings)
    local source_resolve_type = assert(ctx.source_resolve_type)
    local source_infer_expr_type = assert(ctx.source_infer_expr_type)
    local source_infer_value_type = assert(ctx.source_infer_value_type)
    local source_prune_type = assert(ctx.source_prune_type)
    local source_type_name = assert(ctx.source_type_name)
    local source_lower_expr = assert(ctx.source_lower_expr)
    local source_emit_side_effect_expr = assert(ctx.source_emit_side_effect_expr)
    local source_lower_block_void = assert(ctx.source_lower_block_void)
    local source_lower_block_value = assert(ctx.source_lower_block_value)
    local source_block_can_lower_direct_value = assert(ctx.source_block_can_lower_direct_value)
    local source_lower_params = assert(ctx.source_lower_params)
    local source_infer_function_result = assert(ctx.source_infer_function_result)
    local source_require_resolved_type = assert(ctx.source_require_resolved_type)
    local source_bind_local = assert(ctx.source_bind_local)
    local source_lower_function_body = assert(ctx.source_lower_function_body)
    local unwrap_source_item = assert(ctx.unwrap_source_item)
    local source_lower_module_ast = assert(ctx.source_lower_module_ast)
    local source_type = assert(ctx.source_type)
    local source_module = assert(ctx.source_module)
    local quote_expr_capture = assert(ctx.quote_expr_capture)
    local quote_stmt_capture = assert(ctx.quote_stmt_capture)
    local quote_block_capture = assert(ctx.quote_block_capture)
    local is_void_type = assert(ctx.is_void_type)
    local is_ir_quote = assert(ctx.is_ir_quote)

    local function shallow_copy(t)
        local out = {}
        for k, v in pairs(t or {}) do out[k] = v end
        return out
    end

    local function source_quote_merge_env(base_env, bindings)
        return source_merge_host_bindings(base_env, bindings)
    end

    local function source_host_splice_bundle(source, env)
        return { source = source, env = env }
    end

    local SourceTemplateQuoteMT = {}

    local function source_collect_template_holes(ast, host_env)
        local out = {}
        local env = source_new_env(host_env)
        local function walk(node, seen)
            if type(node) ~= "table" then return end
            seen = seen or {}
            if seen[node] then return end
            seen[node] = true
            if node.tag == "hole" then
                local ht = source_resolve_type(node.ty, env)
                local prev = out[node.name]
                assert(prev == nil or prev == ht, ("moonlift quote hole '%s' has conflicting types"):format(node.name))
                out[node.name] = ht
            end
            for _, v in pairs(node) do walk(v, seen) end
        end
        walk(ast, {})
        return out
    end

    local function source_copy_free_holes(hole_types, bindings)
        local out = {}
        for name, t in pairs(hole_types or {}) do
            if bindings == nil or bindings[name] == nil then out[name] = t end
        end
        return out
    end

    local function source_template_validate_binding(self, name, value)
        local want_t = assert(self.hole_types[name], ("moonlift quote has no hole '%s'"):format(name))
        local env = source_new_env(source_quote_merge_env(self.host_env, self.bindings))
        local got_t
        if type(value) == "string" then
            local ast, err = parse_backend_ast(self._backend_ast_expr, value, "quote_binding_expr")
            assert(ast ~= nil, err)
            got_t = source_infer_expr_type(ast, env)
        else
            got_t = source_infer_value_type(value, env)
        end
        got_t = source_prune_type(got_t)
        want_t = source_prune_type(want_t)
        assert(got_t ~= nil and got_t == want_t, (
            "moonlift quote hole '%s' expected %s, got %s"
        ):format(name, source_type_name(want_t), source_type_name(got_t)))
    end

    local function source_template_lookup_mapper(spec, kind)
        if type(spec) == "function" then
            return function(node) return spec(kind, node) end
        end
        if type(spec) ~= "table" then return nil end
        return spec[kind] or spec.any
    end

    local walk_expr
    local walk_stmt
    local walk_type
    local walk_item
    local rewrite_expr
    local rewrite_stmt
    local rewrite_type
    local rewrite_item

    local function walk_apply(spec, kind, node, out)
        local fn = source_template_lookup_mapper(spec, kind)
        if fn == nil then return end
        local value = fn(node)
        if out ~= nil and value ~= nil then out[#out + 1] = value end
    end

    walk_type = function(node, spec, out)
        if type(node) ~= "table" then return end
        walk_apply(spec, "type", node, out)
        if node.tag == "pointer" then
            walk_type(node.inner, spec, out)
        elseif node.tag == "array" then
            walk_expr(node.len, spec, out)
            walk_type(node.elem, spec, out)
        elseif node.tag == "slice" then
            walk_type(node.elem, spec, out)
        elseif node.tag == "func_type" then
            for i = 1, #(node.params or {}) do walk_type(node.params[i], spec, out) end
            if node.result ~= nil then walk_type(node.result, spec, out) end
        end
    end

    walk_expr = function(node, spec, out)
        if type(node) ~= "table" then return end
        walk_apply(spec, "expr", node, out)
        if node.tag == "aggregate" then
            if node.ctor ~= nil then
                if node.ctor.tag == "array_ctor" then
                    walk_expr(node.ctor.len, spec, out)
                    walk_type(node.ctor.elem, spec, out)
                else
                    walk_type(node.ctor, spec, out)
                end
            end
            for i = 1, #(node.fields or {}) do walk_expr(node.fields[i].value, spec, out) end
        elseif node.tag == "cast" or node.tag == "trunc" or node.tag == "zext" or node.tag == "sext" or node.tag == "bitcast" then
            walk_type(node.ty, spec, out)
            walk_expr(node.value, spec, out)
        elseif node.tag == "sizeof" or node.tag == "alignof" then
            walk_type(node.ty, spec, out)
        elseif node.tag == "offsetof" then
            walk_type(node.ty, spec, out)
        elseif node.tag == "load" then
            walk_type(node.ty, spec, out)
            walk_expr(node.ptr, spec, out)
        elseif node.tag == "memcmp" then
            walk_expr(node.a, spec, out)
            walk_expr(node.b, spec, out)
            walk_expr(node.len, spec, out)
        elseif node.tag == "block" then
            for i = 1, #(node.stmts or {}) do walk_stmt(node.stmts[i], spec, out) end
        elseif node.tag == "if" then
            for i = 1, #(node.branches or {}) do
                walk_expr(node.branches[i].cond, spec, out)
                walk_expr(node.branches[i].value, spec, out)
            end
            walk_expr(node.else_value or node.else_branch, spec, out)
        elseif node.tag == "switch" then
            walk_expr(node.value, spec, out)
            for i = 1, #(node.cases or {}) do
                walk_expr(node.cases[i].value, spec, out)
                walk_expr(node.cases[i].body, spec, out)
            end
            walk_expr(node.default, spec, out)
        elseif node.tag == "loop_expr" then
            local head = node.head or {}
            if head.tag == "while" then
                for i = 1, #(head.vars or {}) do
                    walk_type(head.vars[i].ty, spec, out)
                    walk_expr(head.vars[i].init, spec, out)
                end
                walk_expr(head.cond, spec, out)
            elseif head.tag == "over" then
                walk_expr(head.domain, spec, out)
                for i = 1, #(head.carries or {}) do
                    walk_type(head.carries[i].ty, spec, out)
                    walk_expr(head.carries[i].init, spec, out)
                end
            end
            for i = 1, #(node.body.stmts or {}) do walk_stmt(node.body.stmts[i], spec, out) end
            for i = 1, #(node.next or {}) do walk_expr(node.next[i].value, spec, out) end
            walk_expr(node.result, spec, out)
        elseif node.tag == "unary" then
            walk_expr(node.expr, spec, out)
        elseif node.tag == "binary" then
            walk_expr(node.lhs, spec, out)
            walk_expr(node.rhs, spec, out)
        elseif node.tag == "field" then
            walk_expr(node.base, spec, out)
        elseif node.tag == "index" then
            walk_expr(node.base, spec, out)
            walk_expr(node.index, spec, out)
        elseif node.tag == "call" then
            walk_expr(node.callee, spec, out)
            for i = 1, #(node.args or {}) do walk_expr(node.args[i], spec, out) end
        elseif node.tag == "method_call" then
            walk_expr(node.receiver, spec, out)
            for i = 1, #(node.args or {}) do walk_expr(node.args[i], spec, out) end
        elseif node.tag == "hole" then
            walk_type(node.ty, spec, out)
        elseif node.tag == "anonymous_func" then
            for i = 1, #(node.func.sig.params or {}) do walk_type(node.func.sig.params[i].ty, spec, out) end
            if node.func.sig.result ~= nil then walk_type(node.func.sig.result, spec, out) end
            for i = 1, #(node.func.body.stmts or {}) do walk_stmt(node.func.body.stmts[i], spec, out) end
        end
    end

    walk_stmt = function(node, spec, out)
        if type(node) ~= "table" then return end
        walk_apply(spec, "stmt", node, out)
        if node.tag == "let" or node.tag == "var" then
            if node.ty ~= nil then walk_type(node.ty, spec, out) end
            walk_expr(node.value, spec, out)
        elseif node.tag == "assign" then
            walk_expr(node.target, spec, out)
            walk_expr(node.value, spec, out)
        elseif node.tag == "expr" then
            walk_expr(node.expr, spec, out)
        elseif node.tag == "if" then
            for i = 1, #(node.branches or {}) do
                walk_expr(node.branches[i].cond, spec, out)
                for j = 1, #(node.branches[i].body.stmts or {}) do walk_stmt(node.branches[i].body.stmts[j], spec, out) end
            end
            for i = 1, #((node.else_body and node.else_body.stmts) or {}) do walk_stmt(node.else_body.stmts[i], spec, out) end
        elseif node.tag == "while" then
            walk_expr(node.cond, spec, out)
            for i = 1, #(node.body.stmts or {}) do walk_stmt(node.body.stmts[i], spec, out) end
        elseif node.tag == "for" then
            walk_expr(node.start, spec, out)
            walk_expr(node.finish, spec, out)
            if node.step ~= nil then walk_expr(node.step, spec, out) end
            for i = 1, #(node.body.stmts or {}) do walk_stmt(node.body.stmts[i], spec, out) end
        elseif node.tag == "loop" then
            local head = node.head or {}
            if head.tag == "while" then
                for i = 1, #(head.vars or {}) do
                    walk_type(head.vars[i].ty, spec, out)
                    walk_expr(head.vars[i].init, spec, out)
                end
                walk_expr(head.cond, spec, out)
            elseif head.tag == "over" then
                walk_expr(head.domain, spec, out)
                for i = 1, #(head.carries or {}) do
                    walk_type(head.carries[i].ty, spec, out)
                    walk_expr(head.carries[i].init, spec, out)
                end
            end
            for i = 1, #(node.body.stmts or {}) do walk_stmt(node.body.stmts[i], spec, out) end
            for i = 1, #(node.next or {}) do walk_expr(node.next[i].value, spec, out) end
        elseif node.tag == "switch" then
            walk_expr(node.value, spec, out)
            for i = 1, #(node.cases or {}) do
                walk_expr(node.cases[i].value, spec, out)
                for j = 1, #(node.cases[i].body.stmts or {}) do walk_stmt(node.cases[i].body.stmts[j], spec, out) end
            end
            for i = 1, #((node.default and node.default.stmts) or {}) do walk_stmt(node.default.stmts[i], spec, out) end
        elseif node.tag == "return" then
            if node.value ~= nil then walk_expr(node.value, spec, out) end
        elseif node.tag == "memcpy" or node.tag == "memmove" then
            walk_expr(node.dst, spec, out)
            walk_expr(node.src, spec, out)
            walk_expr(node.len, spec, out)
        elseif node.tag == "memset" then
            walk_expr(node.dst, spec, out)
            walk_expr(node.byte, spec, out)
            walk_expr(node.len, spec, out)
        elseif node.tag == "store" then
            walk_type(node.ty, spec, out)
            walk_expr(node.dst, spec, out)
            walk_expr(node.value, spec, out)
        end
    end

    walk_item = function(node, spec, out)
        if type(node) ~= "table" then return end
        walk_apply(spec, "item", node, out)
        if node.tag == "const" then
            if node.ty ~= nil then walk_type(node.ty, spec, out) end
            walk_expr(node.value, spec, out)
        elseif node.tag == "type_alias" then
            walk_type(node.ty, spec, out)
        elseif node.tag == "struct" or node.tag == "union" then
            for i = 1, #(node.fields or {}) do walk_type(node.fields[i].ty, spec, out) end
        elseif node.tag == "tagged_union" then
            if node.base_ty ~= nil then walk_type(node.base_ty, spec, out) end
            for i = 1, #(node.variants or {}) do
                for j = 1, #(node.variants[i].fields or {}) do walk_type(node.variants[i].fields[j].ty, spec, out) end
            end
        elseif node.tag == "enum" then
            if node.base_ty ~= nil then walk_type(node.base_ty, spec, out) end
            for i = 1, #(node.members or {}) do if node.members[i].value ~= nil then walk_expr(node.members[i].value, spec, out) end end
        elseif node.tag == "slice_decl" then
            walk_type(node.ty, spec, out)
        elseif node.tag == "extern_func" then
            for i = 1, #(node.params or {}) do walk_type(node.params[i].ty, spec, out) end
            if node.result ~= nil then walk_type(node.result, spec, out) end
        elseif node.tag == "func" then
            for i = 1, #(node.sig.params or {}) do walk_type(node.sig.params[i].ty, spec, out) end
            if node.sig.result ~= nil then walk_type(node.sig.result, spec, out) end
            for i = 1, #(node.body.stmts or {}) do walk_stmt(node.body.stmts[i], spec, out) end
        elseif node.tag == "impl" then
            for i = 1, #(node.items or {}) do walk_item(node.items[i].item or node.items[i], spec, out) end
        end
    end

    local function rewrite_apply(spec, kind, node)
        local fn = source_template_lookup_mapper(spec, kind)
        if fn == nil then return node end
        local replacement = fn(node)
        if replacement == nil then return node end
        return attach_ast_meta(replacement)
    end

    local function rewrite_type_ctor(node, spec)
        if type(node) ~= "table" then return node end
        if node.tag == "array_ctor" then
            local out = shallow_copy(node)
            out.len = rewrite_expr(node.len, spec)
            out.elem = rewrite_type(node.elem, spec)
            return out
        end
        return rewrite_type(node, spec)
    end

    rewrite_type = function(node, spec)
        if type(node) ~= "table" then return node end
        local out = shallow_copy(node)
        if node.tag == "pointer" then
            out.inner = rewrite_type(node.inner, spec)
        elseif node.tag == "array" then
            out.len = rewrite_expr(node.len, spec)
            out.elem = rewrite_type(node.elem, spec)
        elseif node.tag == "slice" then
            out.elem = rewrite_type(node.elem, spec)
        elseif node.tag == "func_type" then
            out.params = {}
            for i = 1, #(node.params or {}) do out.params[i] = rewrite_type(node.params[i], spec) end
            out.result = node.result and rewrite_type(node.result, spec) or nil
        end
        return rewrite_apply(spec, "type", out)
    end

    rewrite_expr = function(node, spec)
        if type(node) ~= "table" then return node end
        local out = shallow_copy(node)
        if node.tag == "aggregate" then
            out.ctor = rewrite_type_ctor(node.ctor, spec)
            out.fields = {}
            for i = 1, #(node.fields or {}) do
                local field = shallow_copy(node.fields[i])
                field.value = rewrite_expr(field.value, spec)
                out.fields[i] = field
            end
        elseif node.tag == "cast" or node.tag == "trunc" or node.tag == "zext" or node.tag == "sext" or node.tag == "bitcast" then
            out.ty = rewrite_type(node.ty, spec)
            out.value = rewrite_expr(node.value, spec)
        elseif node.tag == "sizeof" or node.tag == "alignof" then
            out.ty = rewrite_type(node.ty, spec)
        elseif node.tag == "offsetof" then
            out.ty = rewrite_type(node.ty, spec)
        elseif node.tag == "load" then
            out.ty = rewrite_type(node.ty, spec)
            out.ptr = rewrite_expr(node.ptr, spec)
        elseif node.tag == "memcmp" then
            out.a = rewrite_expr(node.a, spec)
            out.b = rewrite_expr(node.b, spec)
            out.len = rewrite_expr(node.len, spec)
        elseif node.tag == "block" then
            out.stmts = {}
            for i = 1, #(node.stmts or {}) do out.stmts[i] = rewrite_stmt(node.stmts[i], spec) end
        elseif node.tag == "if" then
            out.branches = {}
            for i = 1, #(node.branches or {}) do
                out.branches[i] = {
                    cond = rewrite_expr(node.branches[i].cond, spec),
                    value = rewrite_expr(node.branches[i].value, spec),
                    span = node.branches[i].span,
                }
            end
            local else_key = node.else_value ~= nil and "else_value" or "else_branch"
            out[else_key] = rewrite_expr(node[else_key], spec)
        elseif node.tag == "switch" then
            out.value = rewrite_expr(node.value, spec)
            out.cases = {}
            for i = 1, #(node.cases or {}) do
                out.cases[i] = {
                    value = rewrite_expr(node.cases[i].value, spec),
                    body = rewrite_expr(node.cases[i].body, spec),
                    span = node.cases[i].span,
                }
            end
            out.default = rewrite_expr(node.default, spec)
        elseif node.tag == "loop_expr" then
            local head = shallow_copy(node.head or {})
            if head.tag == "while" then
                head.vars = {}
                for i = 1, #(node.head.vars or {}) do
                    local v = shallow_copy(node.head.vars[i])
                    v.ty = rewrite_type(v.ty, spec)
                    v.init = rewrite_expr(v.init, spec)
                    head.vars[i] = v
                end
                head.cond = rewrite_expr(node.head.cond, spec)
            elseif head.tag == "over" then
                head.domain = rewrite_expr(node.head.domain, spec)
                head.carries = {}
                for i = 1, #(node.head.carries or {}) do
                    local v = shallow_copy(node.head.carries[i])
                    v.ty = rewrite_type(v.ty, spec)
                    v.init = rewrite_expr(v.init, spec)
                    head.carries[i] = v
                end
            end
            out.head = head
            out.body = { stmts = {} }
            for i = 1, #(node.body.stmts or {}) do out.body.stmts[i] = rewrite_stmt(node.body.stmts[i], spec) end
            out.next = {}
            for i = 1, #(node.next or {}) do
                local entry = shallow_copy(node.next[i])
                entry.value = rewrite_expr(entry.value, spec)
                out.next[i] = entry
            end
            out.result = rewrite_expr(node.result, spec)
        elseif node.tag == "unary" then
            out.expr = rewrite_expr(node.expr, spec)
        elseif node.tag == "binary" then
            out.lhs = rewrite_expr(node.lhs, spec)
            out.rhs = rewrite_expr(node.rhs, spec)
        elseif node.tag == "field" then
            out.base = rewrite_expr(node.base, spec)
        elseif node.tag == "index" then
            out.base = rewrite_expr(node.base, spec)
            out.index = rewrite_expr(node.index, spec)
        elseif node.tag == "call" then
            out.callee = rewrite_expr(node.callee, spec)
            out.args = {}
            for i = 1, #(node.args or {}) do out.args[i] = rewrite_expr(node.args[i], spec) end
        elseif node.tag == "method_call" then
            out.receiver = rewrite_expr(node.receiver, spec)
            out.args = {}
            for i = 1, #(node.args or {}) do out.args[i] = rewrite_expr(node.args[i], spec) end
        elseif node.tag == "hole" then
            out.ty = rewrite_type(node.ty, spec)
        elseif node.tag == "anonymous_func" then
            local func = shallow_copy(node.func)
            local sig = shallow_copy(func.sig)
            sig.params = {}
            for i = 1, #(func.sig.params or {}) do
                local p = shallow_copy(func.sig.params[i])
                p.ty = rewrite_type(p.ty, spec)
                sig.params[i] = p
            end
            sig.result = func.sig.result and rewrite_type(func.sig.result, spec) or nil
            func.sig = sig
            func.body = { stmts = {} }
            for i = 1, #(node.func.body.stmts or {}) do func.body.stmts[i] = rewrite_stmt(node.func.body.stmts[i], spec) end
            out.func = func
        end
        return rewrite_apply(spec, "expr", out)
    end

    rewrite_stmt = function(node, spec)
        if type(node) ~= "table" then return node end
        local out = shallow_copy(node)
        if node.tag == "let" or node.tag == "var" then
            out.ty = node.ty and rewrite_type(node.ty, spec) or nil
            out.value = rewrite_expr(node.value, spec)
        elseif node.tag == "assign" then
            out.target = rewrite_expr(node.target, spec)
            out.value = rewrite_expr(node.value, spec)
        elseif node.tag == "expr" then
            out.expr = rewrite_expr(node.expr, spec)
        elseif node.tag == "if" then
            out.branches = {}
            for i = 1, #(node.branches or {}) do
                local branch = shallow_copy(node.branches[i])
                branch.cond = rewrite_expr(branch.cond, spec)
                branch.body = { stmts = {} }
                for j = 1, #(node.branches[i].body.stmts or {}) do branch.body.stmts[j] = rewrite_stmt(node.branches[i].body.stmts[j], spec) end
                out.branches[i] = branch
            end
            out.else_body = node.else_body and { stmts = {} } or nil
            for i = 1, #((node.else_body and node.else_body.stmts) or {}) do out.else_body.stmts[i] = rewrite_stmt(node.else_body.stmts[i], spec) end
        elseif node.tag == "while" then
            out.cond = rewrite_expr(node.cond, spec)
            out.body = { stmts = {} }
            for i = 1, #(node.body.stmts or {}) do out.body.stmts[i] = rewrite_stmt(node.body.stmts[i], spec) end
        elseif node.tag == "for" then
            out.start = rewrite_expr(node.start, spec)
            out.finish = rewrite_expr(node.finish, spec)
            out.step = node.step and rewrite_expr(node.step, spec) or nil
            out.body = { stmts = {} }
            for i = 1, #(node.body.stmts or {}) do out.body.stmts[i] = rewrite_stmt(node.body.stmts[i], spec) end
        elseif node.tag == "loop" then
            local head = shallow_copy(node.head or {})
            if head.tag == "while" then
                head.vars = {}
                for i = 1, #(node.head.vars or {}) do
                    local v = shallow_copy(node.head.vars[i])
                    v.ty = rewrite_type(v.ty, spec)
                    v.init = rewrite_expr(v.init, spec)
                    head.vars[i] = v
                end
                head.cond = rewrite_expr(node.head.cond, spec)
            elseif head.tag == "over" then
                head.domain = rewrite_expr(node.head.domain, spec)
                head.carries = {}
                for i = 1, #(node.head.carries or {}) do
                    local v = shallow_copy(node.head.carries[i])
                    v.ty = rewrite_type(v.ty, spec)
                    v.init = rewrite_expr(v.init, spec)
                    head.carries[i] = v
                end
            end
            out.head = head
            out.body = { stmts = {} }
            for i = 1, #(node.body.stmts or {}) do out.body.stmts[i] = rewrite_stmt(node.body.stmts[i], spec) end
            out.next = {}
            for i = 1, #(node.next or {}) do
                local entry = shallow_copy(node.next[i])
                entry.value = rewrite_expr(entry.value, spec)
                out.next[i] = entry
            end
        elseif node.tag == "switch" then
            out.value = rewrite_expr(node.value, spec)
            out.cases = {}
            for i = 1, #(node.cases or {}) do
                local case = shallow_copy(node.cases[i])
                case.value = rewrite_expr(case.value, spec)
                case.body = { stmts = {} }
                for j = 1, #(node.cases[i].body.stmts or {}) do case.body.stmts[j] = rewrite_stmt(node.cases[i].body.stmts[j], spec) end
                out.cases[i] = case
            end
            out.default = node.default and { stmts = {} } or nil
            for i = 1, #((node.default and node.default.stmts) or {}) do out.default.stmts[i] = rewrite_stmt(node.default.stmts[i], spec) end
        elseif node.tag == "return" then
            out.value = node.value and rewrite_expr(node.value, spec) or nil
        elseif node.tag == "memcpy" or node.tag == "memmove" then
            out.dst = rewrite_expr(node.dst, spec)
            out.src = rewrite_expr(node.src, spec)
            out.len = rewrite_expr(node.len, spec)
        elseif node.tag == "memset" then
            out.dst = rewrite_expr(node.dst, spec)
            out.byte = rewrite_expr(node.byte, spec)
            out.len = rewrite_expr(node.len, spec)
        elseif node.tag == "store" then
            out.ty = rewrite_type(node.ty, spec)
            out.dst = rewrite_expr(node.dst, spec)
            out.value = rewrite_expr(node.value, spec)
        end
        return rewrite_apply(spec, "stmt", out)
    end

    rewrite_item = function(node, spec)
        if type(node) ~= "table" then return node end
        local out = shallow_copy(node)
        if node.tag == "const" then
            out.ty = node.ty and rewrite_type(node.ty, spec) or nil
            out.value = rewrite_expr(node.value, spec)
        elseif node.tag == "type_alias" then
            out.ty = rewrite_type(node.ty, spec)
        elseif node.tag == "struct" or node.tag == "union" then
            out.fields = {}
            for i = 1, #(node.fields or {}) do
                local field = shallow_copy(node.fields[i])
                field.ty = rewrite_type(field.ty, spec)
                out.fields[i] = field
            end
        elseif node.tag == "tagged_union" then
            out.base_ty = node.base_ty and rewrite_type(node.base_ty, spec) or nil
            out.variants = {}
            for i = 1, #(node.variants or {}) do
                local variant = shallow_copy(node.variants[i])
                variant.fields = {}
                for j = 1, #(node.variants[i].fields or {}) do
                    local field = shallow_copy(node.variants[i].fields[j])
                    field.ty = rewrite_type(field.ty, spec)
                    variant.fields[j] = field
                end
                out.variants[i] = variant
            end
        elseif node.tag == "enum" then
            out.base_ty = node.base_ty and rewrite_type(node.base_ty, spec) or nil
            out.members = {}
            for i = 1, #(node.members or {}) do
                local member = shallow_copy(node.members[i])
                member.value = node.members[i].value and rewrite_expr(node.members[i].value, spec) or nil
                out.members[i] = member
            end
        elseif node.tag == "slice_decl" then
            out.ty = rewrite_type(node.ty, spec)
        elseif node.tag == "extern_func" then
            out.params = {}
            for i = 1, #(node.params or {}) do
                local p = shallow_copy(node.params[i])
                p.ty = rewrite_type(p.ty, spec)
                out.params[i] = p
            end
            out.result = node.result and rewrite_type(node.result, spec) or nil
        elseif node.tag == "func" then
            out.sig = shallow_copy(node.sig)
            out.sig.params = {}
            for i = 1, #(node.sig.params or {}) do
                local p = shallow_copy(node.sig.params[i])
                p.ty = rewrite_type(p.ty, spec)
                out.sig.params[i] = p
            end
            out.sig.result = node.sig.result and rewrite_type(node.sig.result, spec) or nil
            out.body = { stmts = {} }
            for i = 1, #(node.body.stmts or {}) do out.body.stmts[i] = rewrite_stmt(node.body.stmts[i], spec) end
        elseif node.tag == "impl" then
            out.items = {}
            for i = 1, #(node.items or {}) do
                local impl_item = shallow_copy(node.items[i])
                impl_item.item = rewrite_item(node.items[i].item or node.items[i], spec)
                out.items[i] = impl_item
            end
        end
        return rewrite_apply(spec, "item", out)
    end

    local function source_walk_template_quote(self, spec)
        walk_apply(spec, self.kind, self.ast, nil)
        if self.kind == "type" then
            walk_type(self.ast, spec, nil)
        elseif self.kind == "module" then
            for i = 1, #(self.ast.items or {}) do walk_item(self.ast.items[i], spec, nil) end
        end
        return self
    end

    local function source_query_template_quote(self, spec)
        local out = {}
        walk_apply(spec, self.kind, self.ast, out)
        if self.kind == "type" then
            walk_type(self.ast, spec, out)
        elseif self.kind == "module" then
            for i = 1, #(self.ast.items or {}) do walk_item(self.ast.items[i], spec, out) end
        end
        return out
    end

    local function source_rewrite_template_quote(self, spec)
        assert(type(spec) == "function" or type(spec) == "table", ("moonlift.quote.%s:rewrite expects a function or table"):format(self.kind))
        local rewritten_ast
        if self.kind == "type" then
            rewritten_ast = rewrite_type(self.ast, spec)
        elseif self.kind == "module" then
            rewritten_ast = { items = {} }
            for i = 1, #(self.ast.items or {}) do rewritten_ast.items[i] = rewrite_item(self.ast.items[i], spec) end
            rewritten_ast = rewrite_apply(spec, "module", rewritten_ast)
        else
            error(("moonlift.quote.%s:rewrite is not supported"):format(self.kind), 2)
        end
        return setmetatable({
            kind = self.kind,
            source = self.source,
            host_env = self.host_env,
            bindings = shallow_copy(self.bindings or {}),
            hole_types = source_collect_template_holes(rewritten_ast, self.host_env),
            ast = attach_ast_meta(rewritten_ast),
            ast_rewritten = true,
            _materialize = self._materialize,
            _materialize_ast = self._materialize_ast,
            _backend_ast_expr = self._backend_ast_expr,
        }, SourceTemplateQuoteMT)
    end

    local function make_source_template_quote(kind, source, host_env, materialize_fn, materialize_ast_fn, ast, backend_ast_expr)
        ast = attach_ast_meta(ast)
        return setmetatable({
            kind = kind,
            source = source,
            host_env = host_env or _G,
            bindings = {},
            hole_types = source_collect_template_holes(ast, host_env or _G),
            ast = ast,
            ast_rewritten = false,
            _materialize = materialize_fn,
            _materialize_ast = materialize_ast_fn,
            _backend_ast_expr = backend_ast_expr,
        }, SourceTemplateQuoteMT)
    end

    SourceTemplateQuoteMT.__tostring = function(self)
        local bound = 0
        for _ in pairs(self.bindings or {}) do bound = bound + 1 end
        local free = 0
        for _ in pairs(source_copy_free_holes(self.hole_types, self.bindings)) do free = free + 1 end
        return string.format("moonlift.quote.%s<%d bindings, %d holes>", tostring(self.kind), bound, free)
    end

    SourceTemplateQuoteMT.__call = function(self)
        return self:materialize()
    end

    SourceTemplateQuoteMT.__index = {
        bind = function(self, bindings)
            assert(type(bindings) == "table", ("moonlift.quote.%s:bind expects a table"):format(tostring(self.kind)))
            local merged = shallow_copy(self.bindings or {})
            for k, v in pairs(bindings) do
                source_template_validate_binding(self, k, v)
                merged[k] = v
            end
            return setmetatable({
                kind = self.kind,
                source = self.source,
                host_env = self.host_env,
                bindings = merged,
                hole_types = self.hole_types,
                ast = self.ast,
                ast_rewritten = self.ast_rewritten,
                _materialize = self._materialize,
                _materialize_ast = self._materialize_ast,
                _backend_ast_expr = self._backend_ast_expr,
            }, SourceTemplateQuoteMT)
        end,
        subst = function(self, name, value)
            source_template_validate_binding(self, name, value)
            return self:bind({ [name] = value })
        end,
        subst_many = function(self, bindings)
            return self:bind(bindings)
        end,
        materialize = function(self)
            local env = source_quote_merge_env(self.host_env, self.bindings)
            if self.ast_rewritten then
                return self._materialize_ast(clone_ast(self.ast), env)
            end
            return self._materialize(self.source, env)
        end,
        eval = function(self)
            return self:materialize()
        end,
        rewrite = function(self, spec)
            return source_rewrite_template_quote(self, spec)
        end,
        walk = function(self, spec)
            return source_walk_template_quote(self, spec)
        end,
        query = function(self, spec)
            return source_query_template_quote(self, spec)
        end,
        source_text = function(self)
            if self.ast_rewritten then
                if self.kind == "type" then return source_emit.type(self.ast) end
                if self.kind == "module" then return source_emit.module(self.ast) end
            end
            return self.source
        end,
        to_source = function(self)
            return self:source_text()
        end,
        clone_ast = function(self)
            return clone_ast(self.ast)
        end,
        free_holes = function(self)
            return source_copy_free_holes(self.hole_types, self.bindings)
        end,
    }

    local source_emit = {}
    local emit_binary_ops = {
        add = "+",
        sub = "-",
        mul = "*",
        div = "/",
        rem = "%",
        eq = "==",
        ne = "~=",
        lt = "<",
        le = "<=",
        gt = ">",
        ge = ">=",
        ["and"] = "and",
        ["or"] = "or",
        band = "&",
        bor = "|",
        bxor = "~",
        shl = "<<",
        shr = ">>",
        shr_u = ">>>",
    }
    local emit_unary_ops = {
        neg = "-",
        ["not"] = "not ",
        bnot = "~",
        addr_of = "&",
        deref = "*",
    }

    local function emit_quote_string(s)
        return string.format("%q", s)
    end

    local function emit_indent(level)
        return string.rep("    ", level or 0)
    end

    local function emit_append_lines(out, text)
        local line = tostring(text or "")
        if line == "" then
            out[#out + 1] = ""
            return
        end
        for part in (line .. "\n"):gmatch("(.-)\n") do
            out[#out + 1] = part
        end
    end

    local function emit_indent_text(text, level)
        local out = {}
        local pad = emit_indent(level)
        for part in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
            out[#out + 1] = pad .. part
        end
        return table.concat(out, "\n")
    end

    local function emit_push_attr_lines(out, attrs, indent)
        local pad = emit_indent(indent)
        for i = 1, #(attrs or {}) do
            local attr = attrs[i]
            local args = {}
            for j = 1, #(attr.args or {}) do
                local arg = attr.args[j]
                if arg.tag == "ident" then
                    args[j] = arg.value
                elseif arg.tag == "number" then
                    args[j] = arg.value
                elseif arg.tag == "string" then
                    args[j] = emit_quote_string(arg.value)
                else
                    args[j] = tostring(arg.value)
                end
            end
            if #args > 0 then
                out[#out + 1] = pad .. "@" .. tostring(attr.name) .. "(" .. table.concat(args, ", ") .. ")"
            else
                out[#out + 1] = pad .. "@" .. tostring(attr.name)
            end
        end
    end

    function source_emit.path(node)
        return table.concat(node.segments or {}, ".")
    end

    function source_emit.type(node)
        local tag = node and node.tag
        if tag == "path" then
            return source_emit.path(node)
        elseif tag == "pointer" then
            return "&" .. source_emit.type(node.inner)
        elseif tag == "array" then
            return "[" .. source_emit.expr(node.len) .. "]" .. source_emit.type(node.elem)
        elseif tag == "slice" then
            return "[]" .. source_emit.type(node.elem)
        elseif tag == "func_type" then
            local params = {}
            for i = 1, #(node.params or {}) do params[i] = source_emit.type(node.params[i]) end
            local out = "func(" .. table.concat(params, ", ") .. ")"
            if node.result ~= nil then out = out .. " -> " .. source_emit.type(node.result) end
            return out
        elseif tag == "splice" then
            return "@{" .. tostring(node.source) .. "}"
        elseif tag == "group" then
            return "(" .. source_emit.type(node.inner) .. ")"
        end
        error("unsupported source quote type AST tag: " .. tostring(tag), 2)
    end

    function source_emit.type_ctor(node)
        if node.tag == "array_ctor" then
            return "[" .. source_emit.expr(node.len) .. "]" .. source_emit.type(node.elem)
        end
        return source_emit.type(node)
    end

    local function emit_loop_head(head)
        if head.tag == "while" then
            local vars = {}
            for i = 1, #(head.vars or {}) do
                local v = head.vars[i]
                vars[i] = tostring(v.name) .. ": " .. source_emit.type(v.ty) .. " = " .. source_emit.expr(v.init)
            end
            return table.concat(vars, ", ") .. " while " .. source_emit.expr(head.cond)
        elseif head.tag == "over" then
            local carries = {}
            for i = 1, #(head.carries or {}) do
                local v = head.carries[i]
                carries[i] = tostring(v.name) .. ": " .. source_emit.type(v.ty) .. " = " .. source_emit.expr(v.init)
            end
            local suffix = (#carries > 0) and (", " .. table.concat(carries, ", ")) or ""
            return tostring(head.index) .. " over " .. source_emit.expr(head.domain) .. suffix
        end
        error("unsupported source quote loop head tag: " .. tostring(head.tag), 2)
    end

    local function emit_loop_next(lines, next_entries, indent)
        if #(next_entries or {}) == 0 then return end
        local pad = emit_indent(indent)
        lines[#lines + 1] = pad .. "next"
        for i = 1, #(next_entries or {}) do
            local entry = next_entries[i]
            lines[#lines + 1] = emit_indent(indent + 1) .. tostring(entry.name) .. " = " .. source_emit.expr(entry.value)
        end
    end

    function source_emit.expr(node)
        local tag = node and node.tag
        if tag == "path" then
            return source_emit.path(node)
        elseif tag == "number" then
            return tostring(node.raw)
        elseif tag == "bool" then
            return node.value and "true" or "false"
        elseif tag == "nil" then
            return "nil"
        elseif tag == "string" then
            return emit_quote_string(node.value)
        elseif tag == "aggregate" then
            local fields = {}
            for i = 1, #(node.fields or {}) do
                local field = node.fields[i]
                if field.tag == "named" then
                    fields[i] = tostring(field.name) .. " = " .. source_emit.expr(field.value)
                else
                    fields[i] = source_emit.expr(field.value)
                end
            end
            return source_emit.type_ctor(node.ctor) .. " { " .. table.concat(fields, ", ") .. " }"
        elseif tag == "cast" or tag == "trunc" or tag == "zext" or tag == "sext" or tag == "bitcast" then
            return tag .. "<" .. source_emit.type(node.ty) .. ">(" .. source_emit.expr(node.value) .. ")"
        elseif tag == "sizeof" then
            return "sizeof(" .. source_emit.type(node.ty) .. ")"
        elseif tag == "alignof" then
            return "alignof(" .. source_emit.type(node.ty) .. ")"
        elseif tag == "offsetof" then
            return "offsetof(" .. source_emit.type(node.ty) .. ", " .. tostring(node.field) .. ")"
        elseif tag == "load" then
            return "load<" .. source_emit.type(node.ty) .. ">(" .. source_emit.expr(node.ptr) .. ")"
        elseif tag == "memcmp" then
            return "memcmp(" .. source_emit.expr(node.a) .. ", " .. source_emit.expr(node.b) .. ", " .. source_emit.expr(node.len) .. ")"
        elseif tag == "block" then
            local lines = {"do"}
            for i = 1, #(node.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.stmts[i], 1)) end
            lines[#lines + 1] = "end"
            return "(" .. table.concat(lines, "\n") .. ")"
        elseif tag == "if" then
            local lines = {}
            for i = 1, #(node.branches or {}) do
                local branch = node.branches[i]
                lines[#lines + 1] = ((i == 1) and "if " or "elseif ") .. source_emit.expr(branch.cond) .. " then"
                emit_append_lines(lines, emit_indent_text(source_emit.expr(branch.value), 1))
            end
            lines[#lines + 1] = "else"
            emit_append_lines(lines, emit_indent_text(source_emit.expr(node.else_value or node.else_branch), 1))
            lines[#lines + 1] = "end"
            return "(" .. table.concat(lines, "\n") .. ")"
        elseif tag == "switch" then
            local lines = { "switch " .. source_emit.expr(node.value) .. " do" }
            for i = 1, #(node.cases or {}) do
                local case = node.cases[i]
                lines[#lines + 1] = "case " .. source_emit.expr(case.value) .. " then"
                emit_append_lines(lines, emit_indent_text(source_emit.expr(case.body), 1))
            end
            lines[#lines + 1] = "default then"
            emit_append_lines(lines, emit_indent_text(source_emit.expr(node.default), 1))
            lines[#lines + 1] = "end"
            return "(" .. table.concat(lines, "\n") .. ")"
        elseif tag == "loop_expr" then
            local lines = { "loop " .. emit_loop_head(node.head or {}) }
            for i = 1, #(node.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.body.stmts[i], 1)) end
            emit_loop_next(lines, node.next or {}, 0)
            lines[#lines + 1] = "end -> " .. source_emit.expr(node.result)
            return "(" .. table.concat(lines, "\n") .. ")"
        elseif tag == "unary" then
            return "(" .. assert(emit_unary_ops[node.op], "unknown unary op") .. source_emit.expr(node.expr) .. ")"
        elseif tag == "binary" then
            return "(" .. source_emit.expr(node.lhs) .. " " .. assert(emit_binary_ops[node.op], "unknown binary op") .. " " .. source_emit.expr(node.rhs) .. ")"
        elseif tag == "field" then
            return "(" .. source_emit.expr(node.base) .. ")." .. tostring(node.name)
        elseif tag == "index" then
            return "(" .. source_emit.expr(node.base) .. ")[" .. source_emit.expr(node.index) .. "]"
        elseif tag == "call" then
            local args = {}
            for i = 1, #(node.args or {}) do args[i] = source_emit.expr(node.args[i]) end
            return "(" .. source_emit.expr(node.callee) .. ")(" .. table.concat(args, ", ") .. ")"
        elseif tag == "method_call" then
            local args = {}
            for i = 1, #(node.args or {}) do args[i] = source_emit.expr(node.args[i]) end
            return "(" .. source_emit.expr(node.receiver) .. "):" .. tostring(node.method) .. "(" .. table.concat(args, ", ") .. ")"
        elseif tag == "splice" then
            return "@{" .. tostring(node.source) .. "}"
        elseif tag == "hole" then
            return "?" .. tostring(node.name) .. ": " .. source_emit.type(node.ty)
        elseif tag == "anonymous_func" then
            return "(" .. source_emit.func_decl(node.func, 0) .. ")"
        end
        error("unsupported source quote expr AST tag: " .. tostring(tag), 2)
    end

    function source_emit.stmt(node, indent)
        local pad = emit_indent(indent)
        local tag = node and node.tag
        if tag == "let" or tag == "var" then
            return pad .. tag .. " " .. tostring(node.name)
                .. (node.ty and (": " .. source_emit.type(node.ty)) or "")
                .. " = " .. source_emit.expr(node.value)
        elseif tag == "assign" then
            return pad .. source_emit.expr(node.target) .. " = " .. source_emit.expr(node.value)
        elseif tag == "expr" then
            return pad .. source_emit.expr(node.expr)
        elseif tag == "if" then
            local lines = {}
            for i = 1, #(node.branches or {}) do
                local branch = node.branches[i]
                lines[#lines + 1] = pad .. ((i == 1) and "if " or "elseif ") .. source_emit.expr(branch.cond) .. " then"
                for j = 1, #(branch.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(branch.body.stmts[j], indent + 1)) end
            end
            if node.else_body ~= nil then
                lines[#lines + 1] = pad .. "else"
                for i = 1, #(node.else_body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.else_body.stmts[i], indent + 1)) end
            end
            lines[#lines + 1] = pad .. "end"
            return table.concat(lines, "\n")
        elseif tag == "while" then
            local lines = { pad .. "while " .. source_emit.expr(node.cond) .. " do" }
            for i = 1, #(node.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.body.stmts[i], indent + 1)) end
            lines[#lines + 1] = pad .. "end"
            return table.concat(lines, "\n")
        elseif tag == "for" then
            local head = pad .. "for " .. tostring(node.name) .. " = " .. source_emit.expr(node.start) .. ", " .. source_emit.expr(node.finish)
            if node.step ~= nil then head = head .. ", " .. source_emit.expr(node.step) end
            head = head .. " do"
            local lines = { head }
            for i = 1, #(node.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.body.stmts[i], indent + 1)) end
            lines[#lines + 1] = pad .. "end"
            return table.concat(lines, "\n")
        elseif tag == "loop" then
            local lines = { pad .. "loop " .. emit_loop_head(node.head or {}) }
            for i = 1, #(node.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.body.stmts[i], indent + 1)) end
            emit_loop_next(lines, node.next or {}, indent)
            lines[#lines + 1] = pad .. "end"
            return table.concat(lines, "\n")
        elseif tag == "switch" then
            local lines = { pad .. "switch " .. source_emit.expr(node.value) .. " do" }
            for i = 1, #(node.cases or {}) do
                local case = node.cases[i]
                lines[#lines + 1] = pad .. "case " .. source_emit.expr(case.value) .. " then"
                for j = 1, #(case.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(case.body.stmts[j], indent + 1)) end
            end
            if node.default ~= nil then
                lines[#lines + 1] = pad .. "default then"
                for i = 1, #(node.default.stmts or {}) do emit_append_lines(lines, source_emit.stmt(node.default.stmts[i], indent + 1)) end
            end
            lines[#lines + 1] = pad .. "end"
            return table.concat(lines, "\n")
        elseif tag == "break" or tag == "continue" then
            return pad .. tag
        elseif tag == "return" then
            return pad .. "return" .. (node.value and (" " .. source_emit.expr(node.value)) or "")
        elseif tag == "memcpy" or tag == "memmove" then
            return pad .. tag .. "(" .. source_emit.expr(node.dst) .. ", " .. source_emit.expr(node.src) .. ", " .. source_emit.expr(node.len) .. ")"
        elseif tag == "memset" then
            return pad .. "memset(" .. source_emit.expr(node.dst) .. ", " .. source_emit.expr(node.byte) .. ", " .. source_emit.expr(node.len) .. ")"
        elseif tag == "store" then
            return pad .. "store<" .. source_emit.type(node.ty) .. ">(" .. source_emit.expr(node.dst) .. ", " .. source_emit.expr(node.value) .. ")"
        end
        error("unsupported source quote stmt AST tag: " .. tostring(tag), 2)
    end

    function source_emit.func_sig(sig)
        local name = sig.name or {}
        local head = "func "
        if name.tag == "named" then
            head = head .. tostring(name.name)
        elseif name.tag == "method" then
            head = head .. source_emit.path(name.target) .. ":" .. tostring(name.method)
        elseif name.tag ~= "anonymous" then
            error("unsupported source quote function name tag: " .. tostring(name.tag), 2)
        end
        local params = {}
        for i = 1, #(sig.params or {}) do
            params[i] = tostring(sig.params[i].name) .. ": " .. source_emit.type(sig.params[i].ty)
        end
        head = head .. "(" .. table.concat(params, ", ") .. ")"
        if sig.result ~= nil then head = head .. " -> " .. source_emit.type(sig.result) end
        return head
    end

    function source_emit.func_decl(func, indent)
        local pad = emit_indent(indent)
        local lines = { pad .. source_emit.func_sig(func.sig) }
        for i = 1, #(func.body.stmts or {}) do emit_append_lines(lines, source_emit.stmt(func.body.stmts[i], indent + 1)) end
        lines[#lines + 1] = pad .. "end"
        return table.concat(lines, "\n")
    end

    function source_emit.item(node, indent)
        indent = indent or 0
        local pad = emit_indent(indent)
        local lines = {}
        emit_push_attr_lines(lines, node.attrs, indent)
        local vis = (node.visibility == "public") and "pub " or ""
        if node.tag == "const" then
            lines[#lines + 1] = pad .. vis .. "const " .. tostring(node.name)
                .. (node.ty and (": " .. source_emit.type(node.ty)) or "")
                .. " = " .. source_emit.expr(node.value)
        elseif node.tag == "type_alias" then
            lines[#lines + 1] = pad .. vis .. "type " .. tostring(node.name) .. " = " .. source_emit.type(node.ty)
        elseif node.tag == "struct" or node.tag == "union" then
            lines[#lines + 1] = pad .. vis .. node.tag .. " " .. tostring(node.name)
            for i = 1, #(node.fields or {}) do
                lines[#lines + 1] = emit_indent(indent + 1) .. tostring(node.fields[i].name) .. ": " .. source_emit.type(node.fields[i].ty)
            end
            lines[#lines + 1] = pad .. "end"
        elseif node.tag == "tagged_union" then
            local head = pad .. vis .. "tagged union " .. tostring(node.name)
            if node.base_ty ~= nil then head = head .. " : " .. source_emit.type(node.base_ty) end
            lines[#lines + 1] = head
            for i = 1, #(node.variants or {}) do
                local variant = node.variants[i]
                lines[#lines + 1] = emit_indent(indent + 1) .. tostring(variant.name)
                for j = 1, #(variant.fields or {}) do
                    lines[#lines + 1] = emit_indent(indent + 2) .. tostring(variant.fields[j].name) .. ": " .. source_emit.type(variant.fields[j].ty)
                end
                lines[#lines + 1] = emit_indent(indent + 1) .. "end"
            end
            lines[#lines + 1] = pad .. "end"
        elseif node.tag == "enum" then
            local head = pad .. vis .. "enum " .. tostring(node.name)
            if node.base_ty ~= nil then head = head .. " : " .. source_emit.type(node.base_ty) end
            lines[#lines + 1] = head
            for i = 1, #(node.members or {}) do
                local member = tostring(node.members[i].name)
                if node.members[i].value ~= nil then member = member .. " = " .. source_emit.expr(node.members[i].value) end
                lines[#lines + 1] = emit_indent(indent + 1) .. member
            end
            lines[#lines + 1] = pad .. "end"
        elseif node.tag == "opaque" then
            lines[#lines + 1] = pad .. vis .. "opaque " .. tostring(node.name)
        elseif node.tag == "slice_decl" then
            lines[#lines + 1] = pad .. vis .. "slice " .. tostring(node.name) .. " = " .. source_emit.type(node.ty)
        elseif node.tag == "extern_func" then
            local params = {}
            for i = 1, #(node.params or {}) do params[i] = tostring(node.params[i].name) .. ": " .. source_emit.type(node.params[i].ty) end
            local head = pad .. vis .. "extern func " .. tostring(node.name) .. "(" .. table.concat(params, ", ") .. ")"
            if node.result ~= nil then head = head .. " -> " .. source_emit.type(node.result) end
            lines[#lines + 1] = head
        elseif node.tag == "func" then
            lines[#lines + 1] = source_emit.func_decl({ sig = node.sig, body = node.body }, indent):gsub("^" .. pad, pad .. vis, 1)
        elseif node.tag == "impl" then
            lines[#lines + 1] = pad .. vis .. "impl " .. source_emit.path(node.target)
            for i = 1, #(node.items or {}) do
                emit_push_attr_lines(lines, node.items[i].attrs, indent + 1)
                emit_append_lines(lines, source_emit.item(node.items[i].item or node.items[i], indent + 1))
            end
            lines[#lines + 1] = pad .. "end"
        elseif node.tag == "splice_item" then
            lines[#lines + 1] = pad .. "@{" .. tostring(node.source) .. "}"
        else
            error("unsupported source quote item AST tag: " .. tostring(node.tag), 2)
        end
        return table.concat(lines, "\n")
    end

    function source_emit.module(node)
        local items = {}
        for i = 1, #(node.items or {}) do items[i] = source_emit.item(node.items[i], 0) end
        return table.concat(items, "\n\n")
    end

    local function source_mark_ir_quote(qv, kind, source, host_env)
        rawset(qv, "__source_text", source)
        rawset(qv, "__source_host_env", host_env)
        rawset(qv, "__source_quote_kind", kind)
        return qv
    end

    local function source_quote_expr(source, host_env)
        local host = host_env or caller_env(2)
        local env = source_new_env(host)
        local ast, err = parse_backend_ast(ctx.backend_ast_expr, source, "quote_expr")
        assert(ast ~= nil, err)
        return source_mark_ir_quote(quote_expr_capture(function()
            return source_lower_expr(ast, env)
        end), "expr", source, host)
    end

    local function source_quote_stmt(source, host_env)
        local host = host_env or caller_env(2)
        local env = source_new_env(host)
        local ast, err = parse_backend_ast(ctx.backend_ast_expr, source, "quote_stmt")
        if ast == nil then
            ast, err = parse_backend_ast(ctx.backend_ast_expr, "do\n" .. source .. "\nend", "quote_stmt_wrapped")
        end
        assert(ast ~= nil, err)
        return source_mark_ir_quote(quote_stmt_capture(function()
            if ast.tag == "block" then
                source_lower_block_void(ast, source_child_env(env), false, false)
            else
                source_emit_side_effect_expr(source_lower_expr(ast, env))
            end
        end), "stmt", source, host)
    end

    local function source_quote_block(source, host_env)
        local host = host_env or caller_env(2)
        local env = source_new_env(host)
        local ast, err = parse_backend_ast(ctx.backend_ast_expr, source, "quote_block")
        if ast == nil then
            ast, err = parse_backend_ast(ctx.backend_ast_expr, "do\n" .. source .. "\nend", "quote_block_wrapped")
        end
        assert(ast ~= nil, err)
        if ast.tag == "block" and not source_block_can_lower_direct_value(ast) then
            error("moonlift quote.block source fragment must produce a value; use ml.quote.stmt for statement-only blocks", 2)
        end
        return source_mark_ir_quote(quote_block_capture(function()
            if ast.tag == "block" then
                return source_lower_block_value(ast, source_child_env(env), false)
            end
            return source_lower_expr(ast, env)
        end), "block", source, host)
    end

    local function source_quote_func(source, host_env)
        local host = host_env or caller_env(2)
        local env = source_new_env(host)
        local item, err = parse_backend_ast(ctx.backend_ast_code, source, "quote_func")
        assert(item ~= nil, err)
        item = unwrap_source_item(item)
        assert(item.tag == "func", "moonlift.quote.func expects a func item")
        assert(item.sig.name.tag == "anonymous", "moonlift.quote.func expects anonymous func(...) syntax")
        local params = source_lower_params(item.sig.params, env)
        local result_t = item.sig.result and source_resolve_type(item.sig.result, env) or nil
        if result_t == nil then
            local infer_env = source_child_env(env)
            for i = 1, #params do source_bind_local(infer_env, params[i].name, nil, params[i].t, false) end
            result_t = source_require_resolved_type(source_infer_function_result(item, infer_env, "quoted func"), "quoted func result")
        end
        if is_void_type(result_t) then
            return source_mark_ir_quote(quote_stmt_capture {
                params = params,
                body = function(...)
                    local body_env = source_child_env(env)
                    local args = { ... }
                    for i = 1, #params do
                        source_bind_local(body_env, params[i].name, args[i], params[i].t, false)
                    end
                    source_lower_function_body(item, body_env, result_t)
                end,
            }, "func", source, host)
        end
        return source_mark_ir_quote(quote_block_capture {
            params = params,
            body = function(...)
                local body_env = source_child_env(env)
                local args = { ... }
                for i = 1, #params do
                    source_bind_local(body_env, params[i].name, args[i], params[i].t, false)
                end
                return source_lower_function_body(item, body_env, result_t)
            end,
        }, "func", source, host)
    end

    local function source_quote_module_ast(source)
        local ast, err = parse_backend_ast(ctx.backend_ast_module, source, "quote_module")
        assert(ast ~= nil, err)
        local out = clone_ast(ast)
        for i = 1, #(out.items or {}) do out.items[i] = unwrap_source_item(out.items[i]) end
        return attach_ast_meta(out)
    end

    local function source_quote_type(source, host_env)
        local host = host_env or caller_env(2)
        local ast, err = parse_backend_ast(ctx.backend_ast_type, source, "quote_type")
        assert(ast ~= nil, err)
        return make_source_template_quote(
            "type",
            source,
            host,
            source_type,
            function(ast_value, env) return source_resolve_type(ast_value, source_new_env(env)) end,
            ast,
            ctx.backend_ast_expr
        )
    end

    local function source_quote_module(source, host_env)
        local host = host_env or caller_env(2)
        return make_source_template_quote(
            "module",
            source,
            host,
            source_module,
            function(ast_value, env) return source_lower_module_ast(ast_value, env) end,
            source_quote_module_ast(source),
            ctx.backend_ast_expr
        )
    end

    local function maybe_splice_value(value, context, env)
        if is_ir_quote(value) then
            local src = rawget(value, "__source_text")
            local src_kind = rawget(value, "__source_quote_kind")
            local src_env = rawget(value, "__source_host_env")
            if type(src) == "string" and (value._param_count or 0) == 0 then
                local bundle_env = source_quote_merge_env(src_env or env, value.hole_bindings)
                if context == "expr" and (src_kind == "expr" or src_kind == "block") then
                    return source_host_splice_bundle(src, bundle_env)
                end
            end
        end
        if type(value) == "table" and getmetatable(value) == SourceTemplateQuoteMT then
            if value.kind == "type" and context == "type" then
                local src = value.ast_rewritten and source_emit.type(value.ast) or value.source
                return source_host_splice_bundle(src, source_quote_merge_env(value.host_env, value.bindings))
            elseif value.kind == "module" and context == "item" then
                local src = value.ast_rewritten and source_emit.module(value.ast) or value.source
                return source_host_splice_bundle(src, source_quote_merge_env(value.host_env, value.bindings))
            end
        end
        return nil
    end

    return {
        maybe_splice_value = maybe_splice_value,
        quote_api = {
            expr = source_quote_expr,
            stmt = source_quote_stmt,
            block = source_quote_block,
            func = source_quote_func,
            type = source_quote_type,
            module = source_quote_module,
        },
    }
end
