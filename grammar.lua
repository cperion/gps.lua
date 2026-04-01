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

local ffi = require("ffi")
local sub = string.sub
local char = string.char
local concat = table.concat

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
                 | Lit(string text) unique
                 | Num
                 | Str
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

    local function expr_first_key(expr, token_ids)
        local kind = expr.kind
        if kind == "Tok" then
            local id = token_ids[expr.name]
            if not id then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
            return id
        elseif kind == "Lit" then
            if expr.text == "" then return nil end
            return "#b" .. tostring(expr.text:byte(1))
        elseif kind == "Num" then
            return "#num"
        elseif kind == "Str" then
            return "#str"
        end
        return nil
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

                if kind == "Tok" or kind == "Lit" or kind == "Num" or kind == "Str" then
                    local key = expr_first_key(expr, token_ids)
                    if key ~= nil and not inf.first[key] then inf.first[key] = true; changed = true end
                    if kind == "Lit" and expr.text == "" and not inf.nullable then inf.nullable = true; changed = true end
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

            local family = { __gps_reducer = true }

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

        local parser = { __gps_parser = true }

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

    local function detect_parse_mode(rule_map, start)
        local _, rule_order = collect_reachable_rules(rule_map, start)
        local exprs = collect_exprs(rule_order)
        local has_tok, has_direct = false, false
        for i = 1, #exprs do
            local kind = exprs[i].kind
            if kind == "Tok" then has_tok = true end
            if kind == "Lit" or kind == "Num" or kind == "Str" then has_direct = true end
        end
        if has_tok and has_direct then
            error("GPS.grammar: cannot mix Tok with direct terminals (Lit/Num/Str) in one grammar", 2)
        end
        return has_direct and "direct" or "lex"
    end

    local function build_direct_parser(spec, rule_map, start)
        local C_TAB, C_LF, C_CR, C_SPACE = 9, 10, 13, 32
        local C_QUOTE, C_PLUS, C_COMMA, C_MINUS = 34, 43, 44, 45
        local C_DOT, C_0, C_9, C_E = 46, 48, 57, 69
        local C_BSLASH, C_a, C_b, C_e = 92, 97, 98, 101
        local C_f, C_n, C_r, C_t, C_u = 102, 110, 114, 116, 117
        local ESCAPES = {
            [C_QUOTE] = '"', [C_BSLASH] = '\\', [47] = '/',
            [C_b] = '\b', [C_f] = '\f', [C_n] = '\n', [C_r] = '\r', [C_t] = '\t',
        }

        local reachable, rule_order = collect_reachable_rules(rule_map, start)
        local info = compute_nullable_first(rule_map, rule_order, {})
        reject_left_recursion(rule_map, rule_order, info)

        local skip_defs = spec.lex and spec.lex.skip or {}

        local function match_str(input, len, pos, str)
            if pos + #str > len then return false end
            for i = 0, #str - 1 do
                if input[pos + i] ~= str:byte(i + 1) then return false end
            end
            return true
        end

        local function skip_input(param, pos)
            local input, len = param.input, param.len
            while pos < len do
                local advanced = false
                for i = 1, #skip_defs do
                    local skip = skip_defs[i]
                    local kind = skip.kind
                    if kind == "Whitespace" then
                        while pos < len do
                            local c = input[pos]
                            if c == C_SPACE or c == C_TAB or c == C_LF or c == C_CR then
                                pos = pos + 1
                                advanced = true
                            else
                                break
                            end
                        end
                    elseif kind == "LineComment" and match_str(input, len, pos, skip.open) then
                        pos = pos + #skip.open
                        while pos < len and input[pos] ~= C_LF do pos = pos + 1 end
                        if pos < len then pos = pos + 1 end
                        advanced = true
                    elseif kind == "BlockComment" and match_str(input, len, pos, skip.open) then
                        pos = pos + #skip.open
                        while pos < len do
                            if match_str(input, len, pos, skip.close) then
                                pos = pos + #skip.close
                                advanced = true
                                break
                            end
                            pos = pos + 1
                        end
                        advanced = true
                    end
                end
                if not advanced then break end
            end
            return pos
        end

        local function parse_string_value(param, pos, source)
            local input, len = param.input, param.len
            if pos >= len or input[pos] ~= C_QUOTE then return nil, pos end
            pos = pos + 1
            local start_pos = pos
            local has_escape = false
            while pos < len do
                local c = input[pos]
                if c == C_QUOTE then
                    if not has_escape then
                        return sub(source, start_pos + 1, pos), pos + 1
                    end
                    break
                elseif c == C_BSLASH then
                    has_escape = true
                    pos = pos + 2
                else
                    pos = pos + 1
                end
            end
            if has_escape then
                pos = start_pos
                local parts = {}
                local part_start = pos
                while pos < len do
                    local c = input[pos]
                    if c == C_QUOTE then
                        if pos > part_start then parts[#parts + 1] = sub(source, part_start + 1, pos) end
                        return concat(parts), pos + 1
                    elseif c == C_BSLASH then
                        if pos > part_start then parts[#parts + 1] = sub(source, part_start + 1, pos) end
                        pos = pos + 1
                        if pos >= len then return nil, pos end
                        local esc = input[pos]
                        if esc == C_u then
                            if pos + 4 >= len then return nil, pos end
                            local hex = sub(source, pos + 2, pos + 5)
                            local code = tonumber(hex, 16)
                            if code then
                                if code < 128 then
                                    parts[#parts + 1] = char(code)
                                elseif code < 2048 then
                                    parts[#parts + 1] = char(192 + math.floor(code / 64), 128 + code % 64)
                                else
                                    parts[#parts + 1] = char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64)
                                end
                            end
                            pos = pos + 5
                        else
                            parts[#parts + 1] = ESCAPES[esc] or char(esc)
                            pos = pos + 1
                        end
                        part_start = pos
                    else
                        pos = pos + 1
                    end
                end
            end
            return nil, pos
        end

        local function parse_number_value(param, pos, source)
            local input, len = param.input, param.len
            local start_pos = pos
            if pos < len and input[pos] == C_MINUS then pos = pos + 1 end
            if pos < len and input[pos] == C_0 then
                pos = pos + 1
            elseif pos < len and input[pos] > C_0 and input[pos] <= C_9 then
                while pos < len and input[pos] >= C_0 and input[pos] <= C_9 do pos = pos + 1 end
            else
                return nil, start_pos
            end
            if pos < len and input[pos] == C_DOT then
                pos = pos + 1
                if pos >= len or input[pos] < C_0 or input[pos] > C_9 then return nil, start_pos end
                while pos < len and input[pos] >= C_0 and input[pos] <= C_9 do pos = pos + 1 end
            end
            if pos < len and (input[pos] == C_e or input[pos] == C_E) then
                pos = pos + 1
                if pos < len and (input[pos] == C_PLUS or input[pos] == C_MINUS) then pos = pos + 1 end
                if pos >= len or input[pos] < C_0 or input[pos] > C_9 then return nil, start_pos end
                while pos < len and input[pos] >= C_0 and input[pos] <= C_9 do pos = pos + 1 end
            end
            return tonumber(sub(source, start_pos + 1, pos)), pos
        end

        local function compile_input(input_string)
            local len = #input_string
            local input = ffi.new("uint8_t[?]", len)
            ffi.copy(input, input_string, len)
            return { input = input, len = len, source = input_string }
        end

        local function terminal_name(expr)
            if expr.kind == "Lit" then return expr.text end
            if expr.kind == "Num" then return "NUMBER" end
            if expr.kind == "Str" then return "STRING" end
            return expr.name
        end

        local function new_runtime(param, source)
            local rt = { pos = 0, last_end = 0, param = param, source = source }
            function rt:skip()
                self.pos = skip_input(self.param, self.pos)
                return self.pos
            end
            function rt:peek_pos()
                return skip_input(self.param, self.pos)
            end
            function rt:peek_key()
                local pos = skip_input(self.param, self.pos)
                local input, len = self.param.input, self.param.len
                if pos >= len then return nil end
                local b = input[pos]
                if b == C_QUOTE then return "#str" end
                if b == C_MINUS or (b >= C_0 and b <= C_9) then return "#num" end
                return "#b" .. tostring(b)
            end
            return rt
        end

        local function parse_error(rt, source, message)
            local pos = skip_input(rt.param, rt.pos)
            local stop = math.min(#source, pos + 16)
            return false, { pos = pos, text = source:sub(pos + 1, stop), message = message or "parse error" }
        end

        local function build_matcher_runner()
            local rule_fns, expr_fns = {}, {}
            local function compile_expr(expr)
                local cached = expr_fns[expr]
                if cached then return cached end
                local kind, fn = expr.kind
                if kind == "Lit" then
                    local text = expr.text
                    fn = function(rt)
                        local pos = rt:skip()
                        if match_str(rt.param.input, rt.param.len, pos, text) then
                            rt.pos = pos + #text
                            rt.last_end = rt.pos
                            return true
                        end
                        return false
                    end
                elseif kind == "Num" then
                    fn = function(rt)
                        local pos = rt:skip()
                        local value, new_pos = parse_number_value(rt.param, pos, rt.source)
                        if value == nil then return false end
                        rt.pos = new_pos
                        rt.last_end = new_pos
                        return true
                    end
                elseif kind == "Str" then
                    fn = function(rt)
                        local pos = rt:skip()
                        local value, new_pos = parse_string_value(rt.param, pos, rt.source)
                        if value == nil then return false end
                        rt.pos = new_pos
                        rt.last_end = new_pos
                        return true
                    end
                elseif kind == "Ref" then
                    fn = function(rt) return rule_fns[expr.name](rt) end
                elseif kind == "Empty" then
                    fn = function() return true end
                elseif kind == "Optional" then
                    local body = compile_expr(expr.body)
                    fn = function(rt) body(rt); return true end
                elseif kind == "ZeroOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        while true do
                            local mark_pos, mark_end = rt.pos, rt.last_end
                            if not body(rt) then rt.pos, rt.last_end = mark_pos, mark_end; break end
                        end
                        return true
                    end
                elseif kind == "OneOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        if not body(rt) then return false end
                        while true do
                            local mark_pos, mark_end = rt.pos, rt.last_end
                            if not body(rt) then rt.pos, rt.last_end = mark_pos, mark_end; break end
                        end
                        return true
                    end
                elseif kind == "Seq" then
                    local items = {}
                    for i = 1, #expr.items do items[i] = compile_expr(expr.items[i]) end
                    fn = function(rt)
                        local mark_pos, mark_end = rt.pos, rt.last_end
                        for i = 1, #items do
                            if not items[i](rt) then rt.pos, rt.last_end = mark_pos, mark_end; return false end
                        end
                        return true
                    end
                elseif kind == "Choice" then
                    local arms, dispatch, fallback, predictive = {}, {}, nil, true
                    for i = 1, #expr.arms do arms[i] = compile_expr(expr.arms[i]) end
                    for i = 1, #expr.arms do
                        local arm, ainfo = expr.arms[i], info[expr.arms[i]]
                        if ainfo.nullable then if fallback ~= nil then predictive = false; break end; fallback = arms[i] end
                        for key in pairs(ainfo.first) do
                            if dispatch[key] and dispatch[key] ~= arms[i] then predictive = false; break end
                            dispatch[key] = arms[i]
                        end
                        if not predictive then break end
                    end
                    if predictive then
                        fn = function(rt)
                            local arm = dispatch[rt:peek_key()] or fallback
                            if not arm then return false end
                            return arm(rt)
                        end
                    else
                        fn = function(rt)
                            for i = 1, #arms do
                                local mark_pos, mark_end = rt.pos, rt.last_end
                                if arms[i](rt) then return true end
                                rt.pos, rt.last_end = mark_pos, mark_end
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
                rule_fns[rule.name] = function(rt) return body(rt) end
            end
            local start_fn = rule_fns[start]
            return function(param, source)
                local rt = new_runtime(param, source)
                if not start_fn(rt) then return parse_error(rt, source) end
                rt.pos = skip_input(param, rt.pos)
                if rt.pos ~= param.len then return parse_error(rt, source, "trailing input") end
                return true, true
            end
        end

        local function build_reducer(actions)
            actions = actions or {}
            local token_actions = actions.tokens or actions.token or {}
            local rule_actions = actions.rules or actions.rule or {}
            local rule_fns, expr_fns = {}, {}

            local function token_value(rt, expr, start_pos, stop_pos, raw)
                local name = terminal_name(expr)
                local action = token_actions[name]
                if action ~= nil then
                    if type(action) == "function" then return action(rt.source, start_pos, stop_pos, name, rt, raw) end
                    return action
                end
                return raw ~= nil and raw or rt.source:sub(start_pos + 1, stop_pos)
            end
            local function rule_value(name, value, source, start_pos, stop_pos)
                local action = rule_actions[name]
                if action ~= nil then return action(value, source, start_pos, stop_pos, name) end
                return value
            end

            local function compile_expr(expr)
                local cached = expr_fns[expr]
                if cached then return cached end
                local kind, fn = expr.kind
                if kind == "Lit" then
                    local text = expr.text
                    fn = function(rt)
                        local pos = rt:skip()
                        if not match_str(rt.param.input, rt.param.len, pos, text) then return false end
                        rt.pos = pos + #text
                        rt.last_end = rt.pos
                        return true, token_value(rt, expr, pos, rt.pos, text)
                    end
                elseif kind == "Num" then
                    fn = function(rt)
                        local pos = rt:skip()
                        local value, new_pos = parse_number_value(rt.param, pos, rt.source)
                        if value == nil then return false end
                        rt.pos = new_pos
                        rt.last_end = new_pos
                        return true, token_value(rt, expr, pos, new_pos, value)
                    end
                elseif kind == "Str" then
                    fn = function(rt)
                        local pos = rt:skip()
                        local value, new_pos = parse_string_value(rt.param, pos, rt.source)
                        if value == nil then return false end
                        rt.pos = new_pos
                        rt.last_end = new_pos
                        return true, token_value(rt, expr, pos, new_pos, value)
                    end
                elseif kind == "Ref" then
                    fn = function(rt) return rule_fns[expr.name](rt) end
                elseif kind == "Empty" then
                    fn = function() return true, nil end
                elseif kind == "Optional" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local mark_pos, mark_end = rt.pos, rt.last_end
                        local ok, value = body(rt)
                        if ok then return true, value end
                        rt.pos, rt.last_end = mark_pos, mark_end
                        return true, nil
                    end
                elseif kind == "ZeroOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local out = {}
                        while true do
                            local mark_pos, mark_end = rt.pos, rt.last_end
                            local ok, value = body(rt)
                            if not ok then rt.pos, rt.last_end = mark_pos, mark_end; break end
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
                            local mark_pos, mark_end = rt.pos, rt.last_end
                            local next_ok, value = body(rt)
                            if not next_ok then rt.pos, rt.last_end = mark_pos, mark_end; break end
                            if value ~= nil then out[#out + 1] = value end
                        end
                        return true, out
                    end
                elseif kind == "Seq" then
                    local items = {}
                    for i = 1, #expr.items do items[i] = compile_expr(expr.items[i]) end
                    fn = function(rt)
                        local mark_pos, mark_end = rt.pos, rt.last_end
                        local out = {}
                        for i = 1, #items do
                            local ok, value = items[i](rt)
                            if not ok then rt.pos, rt.last_end = mark_pos, mark_end; return false end
                            if value ~= nil then out[#out + 1] = value end
                        end
                        return true, out
                    end
                elseif kind == "Choice" then
                    local arms, dispatch, fallback, predictive = {}, {}, nil, true
                    for i = 1, #expr.arms do arms[i] = compile_expr(expr.arms[i]) end
                    for i = 1, #expr.arms do
                        local ainfo = info[expr.arms[i]]
                        if ainfo.nullable then if fallback ~= nil then predictive = false; break end; fallback = arms[i] end
                        for key in pairs(ainfo.first) do
                            if dispatch[key] and dispatch[key] ~= arms[i] then predictive = false; break end
                            dispatch[key] = arms[i]
                        end
                        if not predictive then break end
                    end
                    if predictive then
                        fn = function(rt)
                            local arm = dispatch[rt:peek_key()] or fallback
                            if not arm then return false end
                            return arm(rt)
                        end
                    else
                        fn = function(rt)
                            for i = 1, #arms do
                                local mark_pos, mark_end = rt.pos, rt.last_end
                                local ok, value = arms[i](rt)
                                if ok then return true, value end
                                rt.pos, rt.last_end = mark_pos, mark_end
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
                    local start_pos = rt:peek_pos()
                    local ok, value = body(rt)
                    if not ok then return false end
                    return true, rule_value(rule.name, value, rt.source, start_pos, rt.last_end)
                end
            end
            local start_fn = rule_fns[start]
            local gen_key = start .. "|direct|reduce"
            local family = { __gps_reducer = true }
            local function run_compiled(param, source)
                local rt = new_runtime(param, source)
                local ok, value = start_fn(rt)
                if not ok then return parse_error(rt, source) end
                rt.pos = skip_input(param, rt.pos)
                if rt.pos ~= param.len then return parse_error(rt, source, "trailing input") end
                return true, value
            end
            function family:try_parse(input_string) return run_compiled(compile_input(input_string), input_string) end
            function family:parse(input_string)
                local ok, value = self:try_parse(input_string)
                if not ok then error(string.format("GPS.grammar parse error at %d near %q (%s)", value.pos or -1, value.text or "", value.message or "error"), 2) end
                return value
            end
            function family:machine(input_string)
                local param = compile_input(input_string)
                return GPS.machine(function(machine_param) return run_compiled(machine_param.direct_param, machine_param.source) end, {
                    direct_param = param,
                    source = input_string,
                }, GPS.EMPTY_STATE, gen_key)
            end
            return family
        end

        local function build_emitter_runner()
            local rule_fns, expr_fns = {}, {}
            local function emit_token(rt, name, start_pos, stop_pos)
                local n = rt.log_n + 1
                rt.log_n = n
                rt.log_kind[n], rt.log_name[n], rt.log_start[n], rt.log_stop[n] = 1, name, start_pos, stop_pos
            end
            local function emit_rule(rt, name, start_pos, stop_pos)
                local n = rt.log_n + 1
                rt.log_n = n
                rt.log_kind[n], rt.log_name[n], rt.log_start[n], rt.log_stop[n] = 2, name, start_pos, stop_pos
            end
            local function compile_expr(expr)
                local cached = expr_fns[expr]
                if cached then return cached end
                local kind, fn = expr.kind
                if kind == "Lit" then
                    local text, name = expr.text, terminal_name(expr)
                    fn = function(rt)
                        local pos = rt:skip()
                        if not match_str(rt.param.input, rt.param.len, pos, text) then return false end
                        rt.pos = pos + #text
                        rt.last_end = rt.pos
                        emit_token(rt, name, pos, rt.pos)
                        return true
                    end
                elseif kind == "Num" then
                    local name = terminal_name(expr)
                    fn = function(rt)
                        local pos = rt:skip()
                        local value, new_pos = parse_number_value(rt.param, pos, rt.source)
                        if value == nil then return false end
                        rt.pos = new_pos
                        rt.last_end = new_pos
                        emit_token(rt, name, pos, new_pos)
                        return true
                    end
                elseif kind == "Str" then
                    local name = terminal_name(expr)
                    fn = function(rt)
                        local pos = rt:skip()
                        local value, new_pos = parse_string_value(rt.param, pos, rt.source)
                        if value == nil then return false end
                        rt.pos = new_pos
                        rt.last_end = new_pos
                        emit_token(rt, name, pos, new_pos)
                        return true
                    end
                elseif kind == "Ref" then
                    fn = function(rt) return rule_fns[expr.name](rt) end
                elseif kind == "Empty" then
                    fn = function() return true end
                elseif kind == "Optional" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        local mark_pos, mark_end, mark_log = rt.pos, rt.last_end, rt.log_n
                        if body(rt) then return true end
                        rt.pos, rt.last_end, rt.log_n = mark_pos, mark_end, mark_log
                        return true
                    end
                elseif kind == "ZeroOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        while true do
                            local mark_pos, mark_end, mark_log = rt.pos, rt.last_end, rt.log_n
                            if not body(rt) then rt.pos, rt.last_end, rt.log_n = mark_pos, mark_end, mark_log; break end
                        end
                        return true
                    end
                elseif kind == "OneOrMore" then
                    local body = compile_expr(expr.body)
                    fn = function(rt)
                        if not body(rt) then return false end
                        while true do
                            local mark_pos, mark_end, mark_log = rt.pos, rt.last_end, rt.log_n
                            if not body(rt) then rt.pos, rt.last_end, rt.log_n = mark_pos, mark_end, mark_log; break end
                        end
                        return true
                    end
                elseif kind == "Seq" then
                    local items = {}
                    for i = 1, #expr.items do items[i] = compile_expr(expr.items[i]) end
                    fn = function(rt)
                        local mark_pos, mark_end, mark_log = rt.pos, rt.last_end, rt.log_n
                        for i = 1, #items do
                            if not items[i](rt) then rt.pos, rt.last_end, rt.log_n = mark_pos, mark_end, mark_log; return false end
                        end
                        return true
                    end
                elseif kind == "Choice" then
                    local arms, dispatch, fallback, predictive = {}, {}, nil, true
                    for i = 1, #expr.arms do arms[i] = compile_expr(expr.arms[i]) end
                    for i = 1, #expr.arms do
                        local ainfo = info[expr.arms[i]]
                        if ainfo.nullable then if fallback ~= nil then predictive = false; break end; fallback = arms[i] end
                        for key in pairs(ainfo.first) do
                            if dispatch[key] and dispatch[key] ~= arms[i] then predictive = false; break end
                            dispatch[key] = arms[i]
                        end
                        if not predictive then break end
                    end
                    if predictive then
                        fn = function(rt)
                            local arm = dispatch[rt:peek_key()] or fallback
                            if not arm then return false end
                            return arm(rt)
                        end
                    else
                        fn = function(rt)
                            for i = 1, #arms do
                                local mark_pos, mark_end, mark_log = rt.pos, rt.last_end, rt.log_n
                                if arms[i](rt) then return true end
                                rt.pos, rt.last_end, rt.log_n = mark_pos, mark_end, mark_log
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
                    local start_pos = rt:peek_pos()
                    local ok = body(rt)
                    if not ok then return false end
                    emit_rule(rt, rule.name, start_pos, rt.last_end)
                    return true
                end
            end
            local start_fn = rule_fns[start]
            return function(param, source, sink)
                local rt = new_runtime(param, source)
                rt.log_n, rt.log_kind, rt.log_name, rt.log_start, rt.log_stop = 0, {}, {}, {}, {}
                if not start_fn(rt) then return parse_error(rt, source) end
                rt.pos = skip_input(param, rt.pos)
                if rt.pos ~= param.len then return parse_error(rt, source, "trailing input") end
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
            tokens = setmetatable({}, { __index = function(t, name)
                local fn = function(source, start_pos, stop_pos, _, _, raw)
                    return { kind = name, text = raw ~= nil and raw or source:sub(start_pos + 1, stop_pos), start = start_pos, stop = stop_pos }
                end
                rawset(t, name, fn)
                return fn
            end }),
            rules = setmetatable({}, { __index = function(t, name)
                local fn = function(value, _, start_pos, stop_pos)
                    return { kind = name, value = value, start = start_pos, stop = stop_pos }
                end
                rawset(t, name, fn)
                return fn
            end }),
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

        local parser = { __gps_parser = true }
        function parser:match(input_string)
            local ok = run_match(compile_input(input_string), input_string)
            return ok
        end
        function parser:emit(input_string, sink)
            local ok, value = run_emit(compile_input(input_string), input_string, sink)
            if not ok then error(string.format("GPS.grammar parse error at %d near %q (%s)", value.pos or -1, value.text or "", value.message or "error"), 2) end
            return value
        end
        function parser:try_emit(input_string, sink) return run_emit(compile_input(input_string), input_string, sink) end
        function parser:reducer(actions) return reducer_for(actions) end
        function parser:reduce(input_string, actions) return reducer_for(actions):parse(input_string) end
        function parser:try_reduce(input_string, actions) return reducer_for(actions):try_parse(input_string) end
        function parser:tree(input_string) return reducer_for(TREE_ACTIONS):parse(input_string) end
        function parser:try_tree(input_string) return reducer_for(TREE_ACTIONS):try_parse(input_string) end
        parser.parse = parser.tree
        parser.try_parse = parser.try_tree
        function parser:machine(input_string, mode, arg)
            local param = compile_input(input_string)
            mode = mode or "match"
            if mode == "match" then
                return GPS.machine(function(machine_param) return run_match(machine_param.direct_param, machine_param.source) end, {
                    direct_param = param, source = input_string,
                }, GPS.EMPTY_STATE, start .. "|direct|match")
            elseif mode == "emit" then
                return GPS.machine(function(machine_param) return run_emit(machine_param.direct_param, machine_param.source, machine_param.sink) end, {
                    direct_param = param, source = input_string, sink = arg,
                }, GPS.EMPTY_STATE, start .. "|direct|emit")
            elseif mode == "tree" then
                return reducer_for(TREE_ACTIONS):machine(input_string)
            elseif mode == "reduce" then
                return reducer_for(arg):machine(input_string)
            else
                error("GPS.grammar: unknown machine mode '" .. tostring(mode) .. "'", 2)
            end
        end
        parser.lexer = nil
        parser.rules = reachable
        parser.start = start
        parser.mode = "direct"
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
        local mode = detect_parse_mode(rule_map, spec.parse.start)
        if mode == "direct" then
            return build_direct_parser(spec, rule_map, spec.parse.start)
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
