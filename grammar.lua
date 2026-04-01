-- gps/grammar.lua — GPS-native grammar compiler
--
-- Grammar source is itself ASDL.
-- The compiler consumes a grammar AST and produces:
--   - a specialized lexer (via GPS.lex)
--   - a specialized recursive-descent parser with predictive choice fast paths
--
-- First fast subset:
--   Lex: Symbol, Keyword, Ident, Number, String, Whitespace, LineComment, BlockComment
--   Parse: Seq, Choice, ZeroOrMore, OneOrMore, Optional, Ref, Tok, Empty
--
-- Left recursion is rejected.

return function(GPS, asdl_context)
    local M = {}

    local GRAMMAR_SCHEMA = [[
        module Grammar {
            Spec = (Lex lex, Parse parse) unique

            Lex = (TokenDef* tokens, SkipDef* skip) unique
            TokenDef = Symbol(string text) unique
                     | Keyword(string text) unique
                     | Ident(string name) unique
                     | Number(string name) unique
                     | String(string name, string quote) unique

            SkipDef = Whitespace
                    | LineComment(string open) unique
                    | BlockComment(string open, string close) unique

            Parse = (Rule* rules, string start) unique
            Rule = (string name, Expr body) unique

            Expr = Seq(Expr* items) unique
                 | Choice(Expr* arms) unique
                 | ZeroOrMore(Expr body) unique
                 | OneOrMore(Expr body) unique
                 | Optional(Expr body) unique
                 | Ref(string name) unique
                 | Tok(string name) unique
                 | Empty
        }
    ]]

    local CTX = asdl_context.NewContext():Define(GRAMMAR_SCHEMA)

    local function token_name(tok)
        if tok.kind == "Symbol" or tok.kind == "Keyword" then return tok.text end
        return tok.name
    end

    local function get_rule_map(spec)
        local map = {}
        for i = 1, #spec.parse.rules do
            local rule = spec.parse.rules[i]
            map[rule.name] = rule
        end
        return map
    end

    local function collect_rule_refs(expr, out)
        out = out or {}
        local kind = expr.kind
        if kind == "Ref" then
            out[expr.name] = true
        elseif kind == "Seq" then
            for i = 1, #expr.items do collect_rule_refs(expr.items[i], out) end
        elseif kind == "Choice" then
            for i = 1, #expr.arms do collect_rule_refs(expr.arms[i], out) end
        elseif kind == "ZeroOrMore" or kind == "OneOrMore" or kind == "Optional" then
            collect_rule_refs(expr.body, out)
        end
        return out
    end

    local function collect_reachable_rules(rule_map, start)
        local seen, order = {}, {}
        local function visit(name)
            if seen[name] then return end
            local rule = rule_map[name]
            if not rule then error("GPS.grammar: unknown rule '" .. tostring(name) .. "'", 3) end
            seen[name] = true
            order[#order + 1] = rule
            local refs = collect_rule_refs(rule.body)
            for ref in pairs(refs) do visit(ref) end
        end
        visit(start)
        return seen, order
    end

    local function collect_used_tokens(rule_map, start)
        local reachable = {}
        local used = {}

        local function walk_expr(expr)
            local kind = expr.kind
            if kind == "Tok" then
                used[expr.name] = true
            elseif kind == "Ref" then
                if not reachable[expr.name] then
                    reachable[expr.name] = true
                    local rule = rule_map[expr.name]
                    if not rule then error("GPS.grammar: unknown rule '" .. tostring(expr.name) .. "'", 3) end
                    walk_expr(rule.body)
                end
            elseif kind == "Seq" then
                for i = 1, #expr.items do walk_expr(expr.items[i]) end
            elseif kind == "Choice" then
                for i = 1, #expr.arms do walk_expr(expr.arms[i]) end
            elseif kind == "ZeroOrMore" or kind == "OneOrMore" or kind == "Optional" then
                walk_expr(expr.body)
            end
        end

        reachable[start] = true
        walk_expr(rule_map[start].body)
        return used
    end

    local function build_lexer(spec, used_tokens)
        local symbols = {}
        local keywords = {}
        local lex_spec = { whitespace = false }
        local saw_ident, saw_number, saw_string = false, false, false

        for i = 1, #spec.lex.tokens do
            local tok = spec.lex.tokens[i]
            local name = token_name(tok)
            if used_tokens[name] then
                if tok.kind == "Symbol" then
                    symbols[#symbols + 1] = tok.text
                elseif tok.kind == "Keyword" then
                    keywords[#keywords + 1] = tok.text
                elseif tok.kind == "Ident" then
                    if saw_ident then error("GPS.grammar: multiple Ident tokens not yet supported", 3) end
                    lex_spec.ident = true
                    saw_ident = true
                elseif tok.kind == "Number" then
                    if saw_number then error("GPS.grammar: multiple Number tokens not yet supported", 3) end
                    lex_spec.number = true
                    saw_number = true
                elseif tok.kind == "String" then
                    if saw_string then error("GPS.grammar: multiple String tokens not yet supported", 3) end
                    lex_spec.string_quote = tok.quote
                    saw_string = true
                end
            end
        end

        for i = 1, #spec.lex.skip do
            local skip = spec.lex.skip[i]
            if skip.kind == "Whitespace" then
                lex_spec.whitespace = true
            elseif skip.kind == "LineComment" then
                lex_spec.line_comment = skip.open
            elseif skip.kind == "BlockComment" then
                lex_spec.block_comment = { skip.open, skip.close }
            end
        end

        if #symbols > 0 then lex_spec.symbols = table.concat(symbols, " ") end
        if #keywords > 0 then lex_spec.keywords = keywords end
        return GPS.lex(lex_spec)
    end

    local function collect_exprs(rule_order)
        local seen, out = {}, {}
        local function walk(expr)
            if seen[expr] then return end
            seen[expr] = true
            out[#out + 1] = expr
            local kind = expr.kind
            if kind == "Seq" then
                for i = 1, #expr.items do walk(expr.items[i]) end
            elseif kind == "Choice" then
                for i = 1, #expr.arms do walk(expr.arms[i]) end
            elseif kind == "ZeroOrMore" or kind == "OneOrMore" or kind == "Optional" then
                walk(expr.body)
            end
        end
        for i = 1, #rule_order do walk(rule_order[i].body) end
        return out
    end

    local function compute_nullable_first(rule_map, rule_order, token_ids)
        local exprs = collect_exprs(rule_order)
        local info = {}
        for i = 1, #exprs do info[exprs[i]] = { nullable = false, first = {} } end

        local function union(dst, src)
            local changed = false
            for k in pairs(src) do
                if not dst[k] then dst[k] = true; changed = true end
            end
            return changed
        end

        local changed = true
        while changed do
            changed = false
            for i = 1, #exprs do
                local expr = exprs[i]
                local inf = info[expr]
                local kind = expr.kind

                if kind == "Tok" then
                    local id = token_ids[expr.name]
                    if not id then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
                    if not inf.first[id] then inf.first[id] = true; changed = true end
                elseif kind == "Ref" then
                    local rule = rule_map[expr.name]
                    if not rule then error("GPS.grammar: unknown rule '" .. tostring(expr.name) .. "'", 3) end
                    local target = info[rule.body]
                    if target.nullable and not inf.nullable then inf.nullable = true; changed = true end
                    if union(inf.first, target.first) then changed = true end
                elseif kind == "Seq" then
                    local nullable = true
                    for j = 1, #expr.items do
                        local child = info[expr.items[j]]
                        if union(inf.first, child.first) then changed = true end
                        if not child.nullable then nullable = false; break end
                    end
                    if nullable and not inf.nullable then inf.nullable = true; changed = true end
                elseif kind == "Choice" then
                    local nullable = false
                    for j = 1, #expr.arms do
                        local child = info[expr.arms[j]]
                        if union(inf.first, child.first) then changed = true end
                        if child.nullable then nullable = true end
                    end
                    if nullable and not inf.nullable then inf.nullable = true; changed = true end
                elseif kind == "ZeroOrMore" or kind == "Optional" then
                    local child = info[expr.body]
                    if not inf.nullable then inf.nullable = true; changed = true end
                    if union(inf.first, child.first) then changed = true end
                elseif kind == "OneOrMore" then
                    local child = info[expr.body]
                    if child.nullable and not inf.nullable then inf.nullable = true; changed = true end
                    if union(inf.first, child.first) then changed = true end
                elseif kind == "Empty" then
                    if not inf.nullable then inf.nullable = true; changed = true end
                end
            end
        end

        for i = 1, #exprs do
            local expr = exprs[i]
            if (expr.kind == "ZeroOrMore" or expr.kind == "OneOrMore") and info[expr.body].nullable then
                error("GPS.grammar: repetition body is nullable: " .. tostring(expr.kind), 3)
            end
        end

        return info
    end

    local function collect_leading_refs(expr, info, out)
        out = out or {}
        local kind = expr.kind
        if kind == "Ref" then
            out[expr.name] = true
        elseif kind == "Seq" then
            for i = 1, #expr.items do
                local child = expr.items[i]
                collect_leading_refs(child, info, out)
                if not info[child].nullable then break end
            end
        elseif kind == "Choice" then
            for i = 1, #expr.arms do collect_leading_refs(expr.arms[i], info, out) end
        elseif kind == "ZeroOrMore" or kind == "OneOrMore" or kind == "Optional" then
            collect_leading_refs(expr.body, info, out)
        end
        return out
    end

    local function reject_left_recursion(rule_map, rule_order, info)
        local graph = {}
        for i = 1, #rule_order do
            local rule = rule_order[i]
            graph[rule.name] = collect_leading_refs(rule.body, info)
        end

        local visiting, done = {}, {}
        local function visit(name)
            if done[name] then return end
            if visiting[name] then
                error("GPS.grammar: left recursion through rule '" .. tostring(name) .. "'", 3)
            end
            visiting[name] = true
            for ref in pairs(graph[name] or {}) do visit(ref) end
            visiting[name] = nil
            done[name] = true
        end

        for i = 1, #rule_order do visit(rule_order[i].name) end
    end

    local function build_parser(rule_map, start, lexer)
        local token_ids = lexer.TOKEN
        local reachable, rule_order = collect_reachable_rules(rule_map, start)
        local info = compute_nullable_first(rule_map, rule_order, token_ids)
        reject_left_recursion(rule_map, rule_order, info)

        local function new_runtime(param, source)
            local rt = {
                pos = 0,
                tok_kind = -1,
                tok_start = 0,
                tok_stop = 0,
                last_end = 0,
                param = param,
                source = source,
            }
            function rt:advance()
                local new_pos, kind, start_pos, stop_pos = lexer.lex_next(self.param, self.pos)
                if new_pos == nil then
                    self.tok_kind = 0
                    self.tok_start = self.pos
                    self.tok_stop = self.pos
                else
                    self.pos = new_pos
                    self.tok_kind = kind
                    self.tok_start = start_pos
                    self.tok_stop = stop_pos
                end
            end
            return rt
        end

        local function parse_error(rt, source, message)
            return false, {
                pos = rt.tok_start,
                token = lexer.TOKEN_NAME[rt.tok_kind] or tostring(rt.tok_kind),
                text = source:sub(rt.tok_start + 1, rt.tok_stop),
                message = message,
            }
        end

        local function build_matcher_runner()
            local rule_fns = {}
            local expr_fns = {}

            local function compile_expr(expr)
                local cached = expr_fns[expr]
                if cached then return cached end

                local kind = expr.kind
                local fn

                if kind == "Tok" then
                    local id = token_ids[expr.name]
                    if not id then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
                    fn = function(rt)
                        if rt.tok_kind ~= id then return false end
                        rt.last_end = rt.tok_stop
                        rt:advance()
                        return true
                    end

                elseif kind == "Ref" then
                    fn = function(rt)
                        return rule_fns[expr.name](rt)
                    end

                elseif kind == "Empty" then
                    fn = function() return true end

                elseif kind == "Optional" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        body(rt)
                        return true
                    end

                elseif kind == "ZeroOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        while true do
                            local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                            if not body(rt) then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                                break
                            end
                        end
                        return true
                    end

                elseif kind == "OneOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        if not body(rt) then return false end
                        while true do
                            local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                            if not body(rt) then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                                break
                            end
                        end
                        return true
                    end

                elseif kind == "Seq" then
                    local items = {}
                    for i = 1, #expr.items do items[i] = compile_expr(expr.items[i]) end
                    fn = function(rt)
                        local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                        for i = 1, #items do
                            if not items[i](rt) then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                                return false
                            end
                        end
                        return true
                    end

                elseif kind == "Choice" then
                    local arms = {}
                    for i = 1, #expr.arms do arms[i] = compile_expr(expr.arms[i]) end

                    local dispatch = {}
                    local fallback = nil
                    local predictive = true
                    for i = 1, #expr.arms do
                        local arm = expr.arms[i]
                        local ainfo = info[arm]
                        if ainfo.nullable then
                            if fallback ~= nil then predictive = false; break end
                            fallback = arms[i]
                        end
                        for tok in pairs(ainfo.first) do
                            if dispatch[tok] and dispatch[tok] ~= arms[i] then
                                predictive = false; break
                            end
                            dispatch[tok] = arms[i]
                        end
                        if not predictive then break end
                    end

                    if predictive then
                        fn = function(rt)
                            local arm = dispatch[rt.tok_kind] or fallback
                            if not arm then return false end
                            return arm(rt)
                        end
                    else
                        fn = function(rt)
                            for i = 1, #arms do
                                local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                                if arms[i](rt) then return true end
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                            end
                            return false
                        end
                    end
                else
                    error("GPS.grammar: unsupported expr kind '" .. tostring(kind) .. "'", 2)
                end

                expr_fns[expr] = fn
                return fn
            end

            for i = 1, #rule_order do rule_fns[rule_order[i].name] = false end
            for i = 1, #rule_order do
                local rule = rule_order[i]
                local body = compile_expr(rule.body)
                rule_fns[rule.name] = function(rt)
                    return body(rt)
                end
            end

            local start_fn = rule_fns[start]
            return function(param, source)
                local rt = new_runtime(param, source)
                rt:advance()
                if not start_fn(rt) then return parse_error(rt, source) end
                if rt.tok_kind ~= 0 then return parse_error(rt, source, "trailing input") end
                return true, true
            end
        end

        local function build_reducer(actions)
            actions = actions or {}
            local token_actions = actions.tokens or actions.token or {}
            local rule_actions = actions.rules or actions.rule or {}
            local rule_fns = {}
            local expr_fns = {}

            local function token_value(rt, name, start_pos, stop_pos)
                local action = token_actions[name]
                if action ~= nil then
                    if type(action) == "function" then
                        return action(rt.source, start_pos, stop_pos, name, rt)
                    else
                        return action
                    end
                end
                return rt.source:sub(start_pos + 1, stop_pos)
            end

            local function rule_value(name, value, source, start_pos, stop_pos)
                local action = rule_actions[name]
                if action ~= nil then
                    return action(value, source, start_pos, stop_pos, name)
                end
                return value
            end

            local function compile_expr(expr)
                local cached = expr_fns[expr]
                if cached then return cached end

                local kind = expr.kind
                local fn

                if kind == "Tok" then
                    local id = token_ids[expr.name]
                    if not id then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
                    fn = function(rt)
                        if rt.tok_kind ~= id then return false end
                        local start_pos, stop_pos = rt.tok_start, rt.tok_stop
                        local value = token_value(rt, expr.name, start_pos, stop_pos)
                        rt.last_end = stop_pos
                        rt:advance()
                        return true, value
                    end

                elseif kind == "Ref" then
                    fn = function(rt)
                        return rule_fns[expr.name](rt)
                    end

                elseif kind == "Empty" then
                    fn = function() return true, nil end

                elseif kind == "Optional" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                        local ok, value = body(rt)
                        if ok then return true, value end
                        rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                        return true, nil
                    end

                elseif kind == "ZeroOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local out = {}
                        while true do
                            local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                            local ok, value = body(rt)
                            if not ok then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                                break
                            end
                            if value ~= nil then out[#out + 1] = value end
                        end
                        return true, out
                    end

                elseif kind == "OneOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local ok, first = body(rt)
                        if not ok then return false end
                        local out = {}
                        if first ~= nil then out[#out + 1] = first end
                        while true do
                            local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                            local next_ok, value = body(rt)
                            if not next_ok then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                                break
                            end
                            if value ~= nil then out[#out + 1] = value end
                        end
                        return true, out
                    end

                elseif kind == "Seq" then
                    local items = {}
                    for i = 1, #expr.items do items[i] = compile_expr(expr.items[i]) end
                    fn = function(rt)
                        local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                        local out = {}
                        for i = 1, #items do
                            local ok, value = items[i](rt)
                            if not ok then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                                return false
                            end
                            if value ~= nil then out[#out + 1] = value end
                        end
                        return true, out
                    end

                elseif kind == "Choice" then
                    local arms = {}
                    for i = 1, #expr.arms do arms[i] = compile_expr(expr.arms[i]) end

                    local dispatch = {}
                    local fallback = nil
                    local predictive = true
                    for i = 1, #expr.arms do
                        local arm = expr.arms[i]
                        local ainfo = info[arm]
                        if ainfo.nullable then
                            if fallback ~= nil then predictive = false; break end
                            fallback = arms[i]
                        end
                        for tok in pairs(ainfo.first) do
                            if dispatch[tok] and dispatch[tok] ~= arms[i] then
                                predictive = false; break
                            end
                            dispatch[tok] = arms[i]
                        end
                        if not predictive then break end
                    end

                    if predictive then
                        fn = function(rt)
                            local arm = dispatch[rt.tok_kind] or fallback
                            if not arm then return false end
                            return arm(rt)
                        end
                    else
                        fn = function(rt)
                            for i = 1, #arms do
                                local mark_pos, mark_kind, mark_start, mark_stop, mark_end = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end
                                local ok, value = arms[i](rt)
                                if ok then return true, value end
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end = mark_pos, mark_kind, mark_start, mark_stop, mark_end
                            end
                            return false
                        end
                    end
                else
                    error("GPS.grammar: unsupported expr kind '" .. tostring(kind) .. "'", 2)
                end

                expr_fns[expr] = fn
                return fn
            end

            for i = 1, #rule_order do rule_fns[rule_order[i].name] = false end
            for i = 1, #rule_order do
                local rule = rule_order[i]
                local body = compile_expr(rule.body)
                rule_fns[rule.name] = function(rt)
                    local start_pos = rt.tok_start
                    local ok, value = body(rt)
                    if not ok then return false end
                    return true, rule_value(rule.name, value, rt.source, start_pos, rt.last_end)
                end
            end

            local start_fn = rule_fns[start]
            local gen_key = start .. "|reduce"

            local family = {}

            local function run_compiled(param, source)
                local rt = new_runtime(param, source)
                rt:advance()
                local ok, value = start_fn(rt)
                if not ok then return parse_error(rt, source) end
                if rt.tok_kind ~= 0 then return parse_error(rt, source, "trailing input") end
                return true, value
            end

            function family:try_parse(input_string)
                return run_compiled(lexer.compile(input_string), input_string)
            end

            function family:parse(input_string)
                local ok, value = self:try_parse(input_string)
                if not ok then
                    error(string.format("GPS.grammar parse error at %d near %q (%s)",
                        value.pos or -1, value.text or "", value.message or value.token or "error"), 2)
                end
                return value
            end

            function family:machine(input_string)
                local param = lexer.compile(input_string)
                return GPS.machine(function(machine_param)
                    return run_compiled(machine_param.lex_param, machine_param.source)
                end, {
                    lex_param = param,
                    source = input_string,
                }, GPS.EMPTY_STATE, gen_key)
            end

            return family
        end

        local function build_emitter_runner()
            local rule_fns = {}
            local expr_fns = {}

            local function emit_token(rt, name, start_pos, stop_pos)
                local n = rt.log_n + 1
                rt.log_n = n
                rt.log_kind[n] = 1
                rt.log_name[n] = name
                rt.log_start[n] = start_pos
                rt.log_stop[n] = stop_pos
            end

            local function emit_rule(rt, name, start_pos, stop_pos)
                local n = rt.log_n + 1
                rt.log_n = n
                rt.log_kind[n] = 2
                rt.log_name[n] = name
                rt.log_start[n] = start_pos
                rt.log_stop[n] = stop_pos
            end

            local function compile_expr(expr)
                local cached = expr_fns[expr]
                if cached then return cached end

                local kind = expr.kind
                local fn

                if kind == "Tok" then
                    local id = token_ids[expr.name]
                    if not id then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
                    fn = function(rt)
                        if rt.tok_kind ~= id then return false end
                        local start_pos, stop_pos = rt.tok_start, rt.tok_stop
                        emit_token(rt, expr.name, start_pos, stop_pos)
                        rt.last_end = stop_pos
                        rt:advance()
                        return true
                    end

                elseif kind == "Ref" then
                    fn = function(rt)
                        return rule_fns[expr.name](rt)
                    end

                elseif kind == "Empty" then
                    fn = function() return true end

                elseif kind == "Optional" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n
                        if body(rt) then return true end
                        rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n = mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log
                        return true
                    end

                elseif kind == "ZeroOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        while true do
                            local mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n
                            if not body(rt) then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n = mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log
                                break
                            end
                        end
                        return true
                    end

                elseif kind == "OneOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        if not body(rt) then return false end
                        while true do
                            local mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n
                            if not body(rt) then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n = mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log
                                break
                            end
                        end
                        return true
                    end

                elseif kind == "Seq" then
                    local items = {}
                    for i = 1, #expr.items do items[i] = compile_expr(expr.items[i]) end
                    fn = function(rt)
                        local mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n
                        for i = 1, #items do
                            if not items[i](rt) then
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n = mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log
                                return false
                            end
                        end
                        return true
                    end

                elseif kind == "Choice" then
                    local arms = {}
                    for i = 1, #expr.arms do arms[i] = compile_expr(expr.arms[i]) end

                    local dispatch = {}
                    local fallback = nil
                    local predictive = true
                    for i = 1, #expr.arms do
                        local arm = expr.arms[i]
                        local ainfo = info[arm]
                        if ainfo.nullable then
                            if fallback ~= nil then predictive = false; break end
                            fallback = arms[i]
                        end
                        for tok in pairs(ainfo.first) do
                            if dispatch[tok] and dispatch[tok] ~= arms[i] then
                                predictive = false; break
                            end
                            dispatch[tok] = arms[i]
                        end
                        if not predictive then break end
                    end

                    if predictive then
                        fn = function(rt)
                            local arm = dispatch[rt.tok_kind] or fallback
                            if not arm then return false end
                            return arm(rt)
                        end
                    else
                        fn = function(rt)
                            for i = 1, #arms do
                                local mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log = rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n
                                if arms[i](rt) then return true end
                                rt.pos, rt.tok_kind, rt.tok_start, rt.tok_stop, rt.last_end, rt.log_n = mark_pos, mark_kind, mark_start, mark_stop, mark_end, mark_log
                            end
                            return false
                        end
                    end
                else
                    error("GPS.grammar: unsupported expr kind '" .. tostring(kind) .. "'", 2)
                end

                expr_fns[expr] = fn
                return fn
            end

            for i = 1, #rule_order do rule_fns[rule_order[i].name] = false end
            for i = 1, #rule_order do
                local rule = rule_order[i]
                local body = compile_expr(rule.body)
                rule_fns[rule.name] = function(rt)
                    local start_pos = rt.tok_start
                    local ok = body(rt)
                    if not ok then return false end
                    emit_rule(rt, rule.name, start_pos, rt.last_end)
                    return true
                end
            end

            local start_fn = rule_fns[start]
            return function(param, source, sink)
                local rt = new_runtime(param, source)
                rt.log_n = 0
                rt.log_kind = {}
                rt.log_name = {}
                rt.log_start = {}
                rt.log_stop = {}
                rt:advance()
                if not start_fn(rt) then return parse_error(rt, source) end
                if rt.tok_kind ~= 0 then return parse_error(rt, source, "trailing input") end
                if sink then
                    for i = 1, rt.log_n do
                        if rt.log_kind[i] == 1 then
                            local f = sink.token or sink.on_token
                            if f then f(sink, rt.log_name[i], source, rt.log_start[i], rt.log_stop[i]) end
                        else
                            local f = sink.rule or sink.on_rule
                            if f then f(sink, rt.log_name[i], source, rt.log_start[i], rt.log_stop[i]) end
                        end
                    end
                end
                return true, rt.log_n
            end
        end

        local run_match = build_matcher_runner()
        local run_emit = build_emitter_runner()
        local EMPTY_ACTIONS = {}
        local TREE_ACTIONS = {
            tokens = setmetatable({}, {
                __index = function(t, name)
                    local fn = function(source, start_pos, stop_pos)
                        return {
                            kind = name,
                            text = source:sub(start_pos + 1, stop_pos),
                            start = start_pos,
                            stop = stop_pos,
                        }
                    end
                    rawset(t, name, fn)
                    return fn
                end,
            }),
            rules = setmetatable({}, {
                __index = function(t, name)
                    local fn = function(value, _, start_pos, stop_pos)
                        return {
                            kind = name,
                            value = value,
                            start = start_pos,
                            stop = stop_pos,
                        }
                    end
                    rawset(t, name, fn)
                    return fn
                end,
            }),
        }
        local reducer_cache = setmetatable({}, { __mode = "k" })

        local function reducer_for(actions)
            actions = actions or EMPTY_ACTIONS
            local cached = reducer_cache[actions]
            if cached then return cached end
            cached = build_reducer(actions)
            reducer_cache[actions] = cached
            return cached
        end

        local parser = {}

        function parser:match(input_string)
            local ok = run_match(lexer.compile(input_string), input_string)
            return ok
        end

        function parser:emit(input_string, sink)
            local ok, value = run_emit(lexer.compile(input_string), input_string, sink)
            if not ok then
                error(string.format("GPS.grammar parse error at %d near %q (%s)",
                    value.pos or -1, value.text or "", value.message or value.token or "error"), 2)
            end
            return value
        end

        function parser:try_emit(input_string, sink)
            return run_emit(lexer.compile(input_string), input_string, sink)
        end

        function parser:reducer(actions)
            return reducer_for(actions)
        end

        function parser:reduce(input_string, actions)
            return reducer_for(actions):parse(input_string)
        end

        function parser:try_reduce(input_string, actions)
            return reducer_for(actions):try_parse(input_string)
        end

        function parser:tree(input_string)
            return reducer_for(TREE_ACTIONS):parse(input_string)
        end

        function parser:try_tree(input_string)
            return reducer_for(TREE_ACTIONS):try_parse(input_string)
        end

        parser.parse = parser.tree
        parser.try_parse = parser.try_tree

        function parser:machine(input_string, mode, arg)
            local param = lexer.compile(input_string)
            mode = mode or "match"
            if mode == "match" then
                return GPS.machine(function(machine_param)
                    return run_match(machine_param.lex_param, machine_param.source)
                end, {
                    lex_param = param,
                    source = input_string,
                }, GPS.EMPTY_STATE, start .. "|match")
            elseif mode == "emit" then
                return GPS.machine(function(machine_param)
                    return run_emit(machine_param.lex_param, machine_param.source, machine_param.sink)
                end, {
                    lex_param = param,
                    source = input_string,
                    sink = arg,
                }, GPS.EMPTY_STATE, start .. "|emit")
            elseif mode == "tree" then
                return reducer_for(TREE_ACTIONS):machine(input_string)
            elseif mode == "reduce" then
                return reducer_for(arg):machine(input_string)
            else
                error("GPS.grammar: unknown machine mode '" .. tostring(mode) .. "'", 2)
            end
        end

        parser.lexer = lexer
        parser.rules = reachable
        parser.start = start

        return parser
    end

    local function compile(spec)
        if not CTX.Grammar.Spec:isclassof(spec) then
            error("GPS.grammar: expected Grammar.Spec", 2)
        end
        local rule_map = get_rule_map(spec)
        if not rule_map[spec.parse.start] then
            error("GPS.grammar: unknown start rule '" .. tostring(spec.parse.start) .. "'", 2)
        end
        local used_tokens = collect_used_tokens(rule_map, spec.parse.start)
        local lexer = build_lexer(spec, used_tokens)
        return build_parser(rule_map, spec.parse.start, lexer)
    end

    local Api = {}

    local Builder = {}
    function Builder:context() return CTX end
    function Builder:schema() return GRAMMAR_SCHEMA end
    function Builder:compile(spec) return compile(spec) end

    function Api.context() return CTX end
    function Api.schema() return GRAMMAR_SCHEMA end
    function Api.compile(spec) return compile(spec) end
    function Api.new()
        return setmetatable({ Grammar = CTX.Grammar }, {
            __index = function(_, key)
                return Builder[key] or CTX.Grammar[key]
            end,
        })
    end

    return setmetatable(Api, {
        __call = function(_, spec)
            if spec == nil then return Api.new() end
            return compile(spec)
        end,
    })
end
