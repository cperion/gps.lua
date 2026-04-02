-- gps/grammar.lua — grammar compiler rewritten around an explicit executor
--
-- A grammar compiles to a parser executor machine:
--   gen   = stable runner (match / emit / reduce)
--   param = compiled grammar tables + lexer/backend descriptors
--   state = parse cursor + reusable logs
--
-- No runtime closure graph per expression. The grammar is flattened into tables
-- and executed by a small set of stable runners.

local ffi = require("ffi")
local sub = string.sub
local char = string.char
local concat = table.concat

ffi.cdef [[
    typedef struct {
        int pos;
        int tok_kind;
        int tok_start;
        int tok_stop;
        int last_end;
    } GpsGrammarTokenState;
]]

local TokenState = ffi.typeof("GpsGrammarTokenState")

local TAG_EMPTY       = 1
local TAG_TOK         = 2
local TAG_REF         = 3
local TAG_SEQ         = 4
local TAG_CHOICE      = 5
local TAG_OPTIONAL    = 6
local TAG_ZERO_OR_MORE= 7
local TAG_ONE_OR_MORE = 8
local TAG_BETWEEN     = 9
local TAG_SEP_BY      = 10
local TAG_ASSOC       = 11
local TAG_LIT         = 12
local TAG_NUM         = 13
local TAG_STR         = 14

local RESULT_ALL   = 1
local RESULT_INDEX = 2
local RESULT_PAIR  = 3

local MODE_MATCH  = 1
local MODE_EMIT   = 2
local MODE_REDUCE = 3

local C_QUOTE  = string.byte('"')
local C_BSLASH = string.byte('\\')
local C_MINUS  = string.byte('-')
local C_PLUS   = string.byte('+')
local C_DOT    = string.byte('.')
local C_0      = string.byte('0')
local C_9      = string.byte('9')
local C_e      = string.byte('e')
local C_E      = string.byte('E')
local C_u      = string.byte('u')

local ESCAPES = {
    [string.byte('n')]  = "\n",
    [string.byte('r')]  = "\r",
    [string.byte('t')]  = "\t",
    [string.byte('b')]  = "\b",
    [string.byte('f')]  = "\f",
    [string.byte('"')]  = '"',
    [string.byte('\\')] = '\\',
    [string.byte('/')]  = '/',
}

local EMPTY_ACTIONS = { tokens = {}, rules = {} }
local TREE_ACTIONS = { __gps_tree_actions = true }

local PARSER_MT = {}
local REDUCER_MT = {}

local function shallow_copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

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

local function lower_expr(expr, memo)
    local hit = memo[expr]
    if hit then return hit end

    local kind = expr.kind
    local out

    if kind == "Between" then
        out = {
            kind = "Seq",
            items = {
                lower_expr(expr.open, memo),
                lower_expr(expr.body, memo),
                lower_expr(expr.close, memo),
            },
            result_mode = RESULT_INDEX,
            result_a = 2,
        }

    elseif kind == "Assoc" then
        out = {
            kind = "Seq",
            items = {
                lower_expr(expr.key, memo),
                lower_expr(expr.sep, memo),
                lower_expr(expr.value, memo),
            },
            result_mode = RESULT_PAIR,
            result_a = 1,
            result_b = 3,
        }

    elseif kind == "Seq" then
        local items = {}
        for i = 1, #expr.items do
            local child = lower_expr(expr.items[i], memo)
            if child.kind == "Seq" and (child.result_mode == nil or child.result_mode == RESULT_ALL) then
                for j = 1, #child.items do items[#items + 1] = child.items[j] end
            else
                items[#items + 1] = child
            end
        end
        out = {
            kind = "Seq",
            items = items,
            result_mode = expr.result_mode or RESULT_ALL,
            result_a = expr.result_a,
            result_b = expr.result_b,
        }

    elseif kind == "Choice" then
        local arms = {}
        for i = 1, #expr.arms do
            local child = lower_expr(expr.arms[i], memo)
            if child.kind == "Choice" then
                for j = 1, #child.arms do arms[#arms + 1] = child.arms[j] end
            else
                arms[#arms + 1] = child
            end
        end
        out = {
            kind = "Choice",
            arms = arms,
        }

    elseif kind == "Optional" then
        out = { kind = "Optional", body = lower_expr(expr.body, memo) }
    elseif kind == "ZeroOrMore" then
        out = { kind = "ZeroOrMore", body = lower_expr(expr.body, memo) }
    elseif kind == "OneOrMore" then
        out = { kind = "OneOrMore", body = lower_expr(expr.body, memo) }
    elseif kind == "SepBy" then
        out = {
            kind = "SepBy",
            item = lower_expr(expr.item, memo),
            sep = lower_expr(expr.sep, memo),
        }
    else
        out = expr
    end

    memo[expr] = out
    return out
end

local function lower_rule_map(rule_map)
    local memo = {}
    local lowered = {}
    for name, rule in pairs(rule_map) do
        lowered[name] = {
            name = rule.name,
            body = lower_expr(rule.body, memo),
        }
    end
    return lowered
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
    elseif kind == "Between" then
        collect_rule_refs(expr.open, out)
        collect_rule_refs(expr.body, out)
        collect_rule_refs(expr.close, out)
    elseif kind == "SepBy" then
        collect_rule_refs(expr.item, out)
        collect_rule_refs(expr.sep, out)
    elseif kind == "Assoc" then
        collect_rule_refs(expr.key, out)
        collect_rule_refs(expr.sep, out)
        collect_rule_refs(expr.value, out)
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
        elseif kind == "Between" then
            walk_expr(expr.open); walk_expr(expr.body); walk_expr(expr.close)
        elseif kind == "SepBy" then
            walk_expr(expr.item); walk_expr(expr.sep)
        elseif kind == "Assoc" then
            walk_expr(expr.key); walk_expr(expr.sep); walk_expr(expr.value)
        end
    end

    reachable[start] = true
    walk_expr(rule_map[start].body)
    return used
end

local function build_lexer(GPS, spec, used_tokens)
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
        elseif kind == "Between" then
            walk(expr.open); walk(expr.body); walk(expr.close)
        elseif kind == "SepBy" then
            walk(expr.item); walk(expr.sep)
        elseif kind == "Assoc" then
            walk(expr.key); walk(expr.sep); walk(expr.value)
        end
    end
    for i = 1, #rule_order do walk(rule_order[i].body) end
    return out
end

local function direct_terminal_name(expr)
    if expr.kind == "Lit" then return expr.text end
    if expr.kind == "Num" then return "NUMBER" end
    if expr.kind == "Str" then return "STRING" end
    return expr.name
end

local function expr_first_key(expr, token_ids, parse_mode)
    local kind = expr.kind
    if parse_mode == "token" then
        if kind == "Tok" then
            local id = token_ids[expr.name]
            if not id then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
            return id
        end
        return nil
    end

    if kind == "Lit" then
        if expr.text == "" then return nil end
        return "#b" .. tostring(expr.text:byte(1))
    elseif kind == "Num" then
        return "#num"
    elseif kind == "Str" then
        return "#str"
    end
    return nil
end

local function compute_nullable_first(rule_map, rule_order, token_ids, parse_mode)
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
                local key = expr_first_key(expr, token_ids, parse_mode)
                if key ~= nil and not inf.first[key] then inf.first[key] = true; changed = true end

            elseif kind == "Ref" then
                local rule = rule_map[expr.name]
                if not rule then error("GPS.grammar: unknown rule '" .. tostring(expr.name) .. "'", 3) end
                local rinf = info[rule.body]
                if union(inf.first, rinf.first) then changed = true end
                if rinf.nullable and not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "Empty" then
                if not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "Optional" then
                local body_i = info[expr.body]
                if union(inf.first, body_i.first) then changed = true end
                if not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "ZeroOrMore" then
                local body_i = info[expr.body]
                if union(inf.first, body_i.first) then changed = true end
                if not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "OneOrMore" then
                local body_i = info[expr.body]
                if union(inf.first, body_i.first) then changed = true end
                if body_i.nullable and not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "Seq" then
                local all_nullable = true
                for j = 1, #expr.items do
                    local child_i = info[expr.items[j]]
                    if union(inf.first, child_i.first) then changed = true end
                    if not child_i.nullable then all_nullable = false; break end
                end
                if all_nullable and not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "Choice" then
                local any_nullable = false
                for j = 1, #expr.arms do
                    local arm_i = info[expr.arms[j]]
                    if union(inf.first, arm_i.first) then changed = true end
                    if arm_i.nullable then any_nullable = true end
                end
                if any_nullable and not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "Between" then
                local open_i = info[expr.open]
                local body_i = info[expr.body]
                local close_i = info[expr.close]
                if union(inf.first, open_i.first) then changed = true end
                if open_i.nullable then
                    if union(inf.first, body_i.first) then changed = true end
                    if body_i.nullable and union(inf.first, close_i.first) then changed = true end
                end
                if open_i.nullable and body_i.nullable and close_i.nullable and not inf.nullable then
                    inf.nullable = true; changed = true
                end

            elseif kind == "SepBy" then
                local item_i = info[expr.item]
                if union(inf.first, item_i.first) then changed = true end
                if item_i.nullable and not inf.nullable then inf.nullable = true; changed = true end

            elseif kind == "Assoc" then
                local key_i = info[expr.key]
                local sep_i = info[expr.sep]
                local val_i = info[expr.value]
                if union(inf.first, key_i.first) then changed = true end
                if key_i.nullable then
                    if union(inf.first, sep_i.first) then changed = true end
                    if sep_i.nullable and union(inf.first, val_i.first) then changed = true end
                end
                if key_i.nullable and sep_i.nullable and val_i.nullable and not inf.nullable then
                    inf.nullable = true; changed = true
                end
            end
        end
    end

    for i = 1, #exprs do
        local expr = exprs[i]
        if (expr.kind == "ZeroOrMore" or expr.kind == "OneOrMore") and info[expr.body].nullable then
            error("GPS.grammar: repetition body is nullable: " .. tostring(expr.kind), 3)
        end
        if expr.kind == "SepBy" and info[expr.item].nullable then
            error("GPS.grammar: SepBy item is nullable", 3)
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
    elseif kind == "Between" then
        collect_leading_refs(expr.open, info, out)
        if info[expr.open].nullable then
            collect_leading_refs(expr.body, info, out)
            if info[expr.body].nullable then collect_leading_refs(expr.close, info, out) end
        end
    elseif kind == "SepBy" then
        collect_leading_refs(expr.item, info, out)
    elseif kind == "Assoc" then
        collect_leading_refs(expr.key, info, out)
    end
    return out
end

local function reject_left_recursion(rule_order, info)
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
    if has_tok then return "token" end
    return "direct"
end

local function compile_direct_input(input_string)
    local len = #input_string
    local input = ffi.new("uint8_t[?]", len)
    ffi.copy(input, input_string, len)
    return { input = input, len = len, source = input_string }
end

local function compile_skip_defs(spec)
    local out = {}
    for i = 1, #spec.lex.skip do
        local skip = spec.lex.skip[i]
        if skip.kind == "Whitespace" then
            out[#out + 1] = { kind = "Whitespace" }
        elseif skip.kind == "LineComment" then
            out[#out + 1] = { kind = "LineComment", open = skip.open }
        elseif skip.kind == "BlockComment" then
            out[#out + 1] = { kind = "BlockComment", open = skip.open, close = skip.close }
        end
    end
    return out
end

local function match_str(input, len, pos, str)
    if pos + #str > len then return false end
    for i = 0, #str - 1 do
        if input[pos + i] ~= str:byte(i + 1) then return false end
    end
    return true
end

local function is_space(b)
    return b == 32 or b == 9 or b == 10 or b == 13
end

local function skip_direct_input(param, input_param, pos)
    local input, len = input_param.input, input_param.len
    local skip_defs = param.skip_defs
    while pos < len do
        local advanced = false
        for i = 1, #skip_defs do
            local skip = skip_defs[i]
            if skip.kind == "Whitespace" then
                if is_space(input[pos]) then
                    pos = pos + 1
                    while pos < len and is_space(input[pos]) do pos = pos + 1 end
                    advanced = true
                    break
                end
            elseif skip.kind == "LineComment" then
                if match_str(input, len, pos, skip.open) then
                    pos = pos + #skip.open
                    while pos < len and input[pos] ~= 10 do pos = pos + 1 end
                    if pos < len then pos = pos + 1 end
                    advanced = true
                    break
                end
            elseif skip.kind == "BlockComment" then
                if match_str(input, len, pos, skip.open) then
                    pos = pos + #skip.open
                    while pos < len do
                        if match_str(input, len, pos, skip.close) then
                            pos = pos + #skip.close
                            break
                        end
                        pos = pos + 1
                    end
                    advanced = true
                    break
                end
            end
        end
        if not advanced then break end
    end
    return pos
end

local function parse_string_value(input_param, pos, source)
    local input, len = input_param.input, input_param.len
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
                    if not code then return nil, pos end
                    if code < 128 then
                        parts[#parts + 1] = char(code)
                    elseif code < 2048 then
                        parts[#parts + 1] = char(192 + math.floor(code / 64), 128 + code % 64)
                    else
                        parts[#parts + 1] = char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64)
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

local function parse_number_value(input_param, pos, source)
    local input, len = input_param.input, input_param.len
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

local function copy_set(src)
    local out = {}
    for k in pairs(src) do out[k] = true end
    return out
end

local function flatten_grammar(rule_map, start, parse_mode, lexer, spec)
    local reachable, rule_order = collect_reachable_rules(rule_map, start)
    local token_ids = lexer and lexer.TOKEN or nil
    local info = compute_nullable_first(rule_map, rule_order, token_ids, parse_mode)
    reject_left_recursion(rule_order, info)

    local exprs = collect_exprs(rule_order)
    local expr_id_of = {}
    for i = 1, #exprs do expr_id_of[exprs[i]] = i end

    local rule_id_of = {}
    local rule_name = {}
    local rule_expr = {}
    for i = 1, #rule_order do
        local rule = rule_order[i]
        rule_id_of[rule.name] = i
        rule_name[i] = rule.name
        rule_expr[i] = expr_id_of[rule.body]
    end

    local expr_tag = {}
    local expr_a = {}
    local expr_b = {}
    local expr_c = {}
    local child_lo = {}
    local child_len = {}
    local children = {}
    local choice_dispatch = {}
    local choice_fallback = {}
    local expr_name = {}
    local expr_text = {}
    local seq_result_mode = {}
    local seq_result_a = {}
    local seq_result_b = {}
    local nullable = {}
    local first = {}

    local function append_children(list)
        local lo = #children + 1
        for i = 1, #list do children[#children + 1] = expr_id_of[list[i]] end
        return lo, #list
    end

    for i = 1, #exprs do
        local expr = exprs[i]
        nullable[i] = info[expr].nullable
        first[i] = copy_set(info[expr].first)
        local kind = expr.kind

        if kind == "Empty" then
            expr_tag[i] = TAG_EMPTY

        elseif kind == "Tok" then
            expr_tag[i] = TAG_TOK
            expr_a[i] = token_ids[expr.name]
            if not expr_a[i] then error("GPS.grammar: unknown token '" .. tostring(expr.name) .. "'", 3) end
            expr_name[i] = expr.name

        elseif kind == "Ref" then
            expr_tag[i] = TAG_REF
            expr_a[i] = rule_id_of[expr.name]
            if not expr_a[i] then error("GPS.grammar: unknown rule '" .. tostring(expr.name) .. "'", 3) end

        elseif kind == "Seq" then
            expr_tag[i] = TAG_SEQ
            child_lo[i], child_len[i] = append_children(expr.items)
            seq_result_mode[i] = expr.result_mode or RESULT_ALL
            seq_result_a[i] = expr.result_a or 0
            seq_result_b[i] = expr.result_b or 0

        elseif kind == "Choice" then
            expr_tag[i] = TAG_CHOICE
            child_lo[i], child_len[i] = append_children(expr.arms)

            local predictive = true
            local dispatch = {}
            local fallback = 0
            for j = 1, #expr.arms do
                local arm = expr.arms[j]
                local arm_id = expr_id_of[arm]
                local arm_info = info[arm]
                if arm_info.nullable then
                    if fallback ~= 0 then predictive = false; break end
                    fallback = arm_id
                end
                for key in pairs(arm_info.first) do
                    if dispatch[key] and dispatch[key] ~= arm_id then
                        predictive = false
                        break
                    end
                    dispatch[key] = arm_id
                end
                if not predictive then break end
            end
            if predictive then
                choice_dispatch[i] = dispatch
                choice_fallback[i] = fallback
            end

        elseif kind == "Optional" then
            expr_tag[i] = TAG_OPTIONAL
            expr_a[i] = expr_id_of[expr.body]

        elseif kind == "ZeroOrMore" then
            expr_tag[i] = TAG_ZERO_OR_MORE
            expr_a[i] = expr_id_of[expr.body]

        elseif kind == "OneOrMore" then
            expr_tag[i] = TAG_ONE_OR_MORE
            expr_a[i] = expr_id_of[expr.body]

        elseif kind == "Between" then
            expr_tag[i] = TAG_BETWEEN
            expr_a[i] = expr_id_of[expr.open]
            expr_b[i] = expr_id_of[expr.body]
            expr_c[i] = expr_id_of[expr.close]

        elseif kind == "SepBy" then
            expr_tag[i] = TAG_SEP_BY
            expr_a[i] = expr_id_of[expr.item]
            expr_b[i] = expr_id_of[expr.sep]

        elseif kind == "Assoc" then
            expr_tag[i] = TAG_ASSOC
            expr_a[i] = expr_id_of[expr.key]
            expr_b[i] = expr_id_of[expr.sep]
            expr_c[i] = expr_id_of[expr.value]

        elseif kind == "Lit" then
            expr_tag[i] = TAG_LIT
            expr_text[i] = expr.text
            expr_name[i] = direct_terminal_name(expr)

        elseif kind == "Num" then
            expr_tag[i] = TAG_NUM
            expr_name[i] = direct_terminal_name(expr)

        elseif kind == "Str" then
            expr_tag[i] = TAG_STR
            expr_name[i] = direct_terminal_name(expr)

        else
            error("GPS.grammar: unsupported expr kind '" .. tostring(kind) .. "'", 2)
        end
    end

    local param = {
        mode = parse_mode,
        start_rule = rule_id_of[start],
        start_name = start,
        rule_name = rule_name,
        rule_expr = rule_expr,
        expr_tag = expr_tag,
        expr_a = expr_a,
        expr_b = expr_b,
        expr_c = expr_c,
        child_lo = child_lo,
        child_len = child_len,
        children = children,
        choice_dispatch = choice_dispatch,
        choice_fallback = choice_fallback,
        expr_name = expr_name,
        expr_text = expr_text,
        seq_result_mode = seq_result_mode,
        seq_result_a = seq_result_a,
        seq_result_b = seq_result_b,
        nullable = nullable,
        first = first,
        lexer = lexer,
        compile_input = parse_mode == "token" and lexer.compile or compile_direct_input,
        skip_defs = parse_mode == "direct" and compile_skip_defs(spec) or nil,
        token_name_by_id = lexer and shallow_copy(lexer.TOKEN_NAME) or nil,
        reachable = reachable,
    }

    return param
end

local function reset_token_state(state, compiled_input)
    local s = state.cursor
    s.pos = 0
    s.tok_kind = -1
    s.tok_start = 0
    s.tok_stop = 0
    s.last_end = 0
    state.input = compiled_input
    state.log_n = 0
end

local function reset_direct_state(state, compiled_input)
    state.pos = 0
    state.last_end = 0
    state.input = compiled_input
    state.log_n = 0
end

local function new_token_state()
    return {
        cursor = ffi.new(TokenState),
        input = nil,
        log_n = 0,
        log_kind = {},
        log_name = {},
        log_start = {},
        log_stop = {},
    }
end

local function new_direct_state()
    return {
        pos = 0,
        last_end = 0,
        input = nil,
        log_n = 0,
        log_kind = {},
        log_name = {},
        log_start = {},
        log_stop = {},
    }
end

local function token_advance(param, state)
    local s = state.cursor
    local new_pos, kind, start_pos, stop_pos = param.lexer.lex_next(state.input, s.pos)
    if new_pos == nil then
        s.tok_kind = 0
        s.tok_start = s.pos
        s.tok_stop = s.pos
    else
        s.pos = new_pos
        s.tok_kind = kind
        s.tok_start = start_pos
        s.tok_stop = stop_pos
    end
end

local function token_error(state, source, message)
    local s = state.cursor
    local stop = math.min(#source, s.tok_stop + 16)
    return false, {
        pos = s.tok_start,
        text = source:sub(s.tok_start + 1, stop),
        message = message or "parse error",
        token = tostring(s.tok_kind),
    }
end

local function direct_error(param, state, source, message)
    local pos = skip_direct_input(param, state.input, state.pos)
    local stop = math.min(#source, pos + 16)
    return false, {
        pos = pos,
        text = source:sub(pos + 1, stop),
        message = message or "parse error",
    }
end

local function emit_log_token(state, name, start_pos, stop_pos)
    local n = state.log_n + 1
    state.log_n = n
    state.log_kind[n] = 1
    state.log_name[n] = name
    state.log_start[n] = start_pos
    state.log_stop[n] = stop_pos
end

local function emit_log_rule(state, name, start_pos, stop_pos)
    local n = state.log_n + 1
    state.log_n = n
    state.log_kind[n] = 2
    state.log_name[n] = name
    state.log_start[n] = start_pos
    state.log_stop[n] = stop_pos
end

local function replay_emit_log(state, source, sink)
    if not sink then return state.log_n end
    local on_token = sink.token or sink.on_token
    local on_rule = sink.rule or sink.on_rule
    for i = 1, state.log_n do
        if state.log_kind[i] == 1 then
            if on_token then on_token(sink, state.log_name[i], source, state.log_start[i], state.log_stop[i]) end
        else
            if on_rule then on_rule(sink, state.log_name[i], source, state.log_start[i], state.log_stop[i]) end
        end
    end
    return state.log_n
end

local function normalize_actions(actions)
    if actions == TREE_ACTIONS then return TREE_ACTIONS end
    if not actions then return EMPTY_ACTIONS end
    if actions.__gps_normalized_actions then return actions end
    return {
        __gps_normalized_actions = true,
        raw = actions,
        tokens = actions.tokens or actions.token or EMPTY_ACTIONS.tokens,
        rules = actions.rules or actions.rule or EMPTY_ACTIONS.rules,
    }
end

local function apply_token_action(actions, name, source, start_pos, stop_pos, runtime)
    if actions == TREE_ACTIONS then
        return {
            kind = name,
            text = source:sub(start_pos + 1, stop_pos),
            start = start_pos,
            stop = stop_pos,
        }
    end
    local action = actions.tokens[name]
    if action ~= nil then
        if type(action) == "function" then
            return action(source, start_pos, stop_pos, name, runtime)
        end
        return action
    end
    return source:sub(start_pos + 1, stop_pos)
end

local function apply_rule_action(actions, name, value, source, start_pos, stop_pos)
    if actions == TREE_ACTIONS then
        return {
            kind = name,
            value = value,
            start = start_pos,
            stop = stop_pos,
        }
    end
    local action = actions.rules[name]
    if action ~= nil then
        return action(value, source, start_pos, stop_pos, name)
    end
    return value
end

local run_token_reduce, run_token_match, run_token_emit
local run_direct_reduce, run_direct_match, run_direct_emit

local function token_mark(state)
    local s = state.cursor
    return s.pos, s.tok_kind, s.tok_start, s.tok_stop, s.last_end
end

local function token_restore(state, pos, kind, start_pos, stop_pos, last_end)
    local s = state.cursor
    s.pos = pos
    s.tok_kind = kind
    s.tok_start = start_pos
    s.tok_stop = stop_pos
    s.last_end = last_end
end

local function token_choose_arm(param, state, expr_id)
    local dispatch = param.choice_dispatch[expr_id]
    if not dispatch then return nil, false end
    local arm = dispatch[state.cursor.tok_kind] or (param.choice_fallback[expr_id] ~= 0 and param.choice_fallback[expr_id] or nil)
    return arm, true
end

run_token_match = function(param, state, expr_id)
    local tag = param.expr_tag[expr_id]
    local s = state.cursor

    if tag == TAG_EMPTY then
        return true

    elseif tag == TAG_TOK then
        if s.tok_kind ~= param.expr_a[expr_id] then return false end
        s.last_end = s.tok_stop
        token_advance(param, state)
        return true

    elseif tag == TAG_REF then
        return run_token_match(param, state, param.rule_expr[param.expr_a[expr_id]])

    elseif tag == TAG_OPTIONAL then
        local p, k, ts, te, le = token_mark(state)
        if run_token_match(param, state, param.expr_a[expr_id]) then return true end
        token_restore(state, p, k, ts, te, le)
        return true

    elseif tag == TAG_ZERO_OR_MORE then
        local body = param.expr_a[expr_id]
        while true do
            local p, k, ts, te, le = token_mark(state)
            if not run_token_match(param, state, body) then
                token_restore(state, p, k, ts, te, le)
                break
            end
        end
        return true

    elseif tag == TAG_ONE_OR_MORE then
        local body = param.expr_a[expr_id]
        if not run_token_match(param, state, body) then return false end
        while true do
            local p, k, ts, te, le = token_mark(state)
            if not run_token_match(param, state, body) then
                token_restore(state, p, k, ts, te, le)
                break
            end
        end
        return true

    elseif tag == TAG_BETWEEN then
        local p, k, ts, te, le = token_mark(state)
        if not run_token_match(param, state, param.expr_a[expr_id]) or
           not run_token_match(param, state, param.expr_b[expr_id]) or
           not run_token_match(param, state, param.expr_c[expr_id]) then
            token_restore(state, p, k, ts, te, le)
            return false
        end
        return true

    elseif tag == TAG_SEP_BY then
        local item = param.expr_a[expr_id]
        local sep = param.expr_b[expr_id]
        local p, k, ts, te, le = token_mark(state)
        if not run_token_match(param, state, item) then
            token_restore(state, p, k, ts, te, le)
            return false
        end
        while true do
            local mp, mk, mts, mte, mle = token_mark(state)
            if not run_token_match(param, state, sep) or not run_token_match(param, state, item) then
                token_restore(state, mp, mk, mts, mte, mle)
                break
            end
        end
        return true

    elseif tag == TAG_ASSOC then
        local p, k, ts, te, le = token_mark(state)
        if not run_token_match(param, state, param.expr_a[expr_id]) or
           not run_token_match(param, state, param.expr_b[expr_id]) or
           not run_token_match(param, state, param.expr_c[expr_id]) then
            token_restore(state, p, k, ts, te, le)
            return false
        end
        return true

    elseif tag == TAG_SEQ then
        local p, k, ts, te, le = token_mark(state)
        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            if not run_token_match(param, state, param.children[i]) then
                token_restore(state, p, k, ts, te, le)
                return false
            end
        end
        return true

    elseif tag == TAG_CHOICE then
        local chosen, predictive = token_choose_arm(param, state, expr_id)
        if predictive then
            if not chosen then return false end
            return run_token_match(param, state, chosen)
        end

        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            local p, k, ts, te, le = token_mark(state)
            if run_token_match(param, state, param.children[i]) then return true end
            token_restore(state, p, k, ts, te, le)
        end
        return false
    end

    error("GPS.grammar: bad token-match tag " .. tostring(tag), 2)
end

run_token_emit = function(param, state, expr_id)
    local tag = param.expr_tag[expr_id]
    local s = state.cursor

    if tag == TAG_EMPTY then
        return true

    elseif tag == TAG_TOK then
        if s.tok_kind ~= param.expr_a[expr_id] then return false end
        local start_pos, stop_pos = s.tok_start, s.tok_stop
        s.last_end = stop_pos
        token_advance(param, state)
        emit_log_token(state, param.expr_name[expr_id], start_pos, stop_pos)
        return true

    elseif tag == TAG_REF then
        local rule_id = param.expr_a[expr_id]
        local start_pos = s.tok_start
        if not run_token_emit(param, state, param.rule_expr[rule_id]) then return false end
        emit_log_rule(state, param.rule_name[rule_id], start_pos, state.cursor.last_end)
        return true

    elseif tag == TAG_OPTIONAL then
        local p, k, ts, te, le = token_mark(state)
        local mark_log = state.log_n
        if run_token_emit(param, state, param.expr_a[expr_id]) then return true end
        token_restore(state, p, k, ts, te, le)
        state.log_n = mark_log
        return true

    elseif tag == TAG_ZERO_OR_MORE then
        local body = param.expr_a[expr_id]
        while true do
            local p, k, ts, te, le = token_mark(state)
            local mark_log = state.log_n
            if not run_token_emit(param, state, body) then
                token_restore(state, p, k, ts, te, le)
                state.log_n = mark_log
                break
            end
        end
        return true

    elseif tag == TAG_ONE_OR_MORE then
        local body = param.expr_a[expr_id]
        if not run_token_emit(param, state, body) then return false end
        while true do
            local p, k, ts, te, le = token_mark(state)
            local mark_log = state.log_n
            if not run_token_emit(param, state, body) then
                token_restore(state, p, k, ts, te, le)
                state.log_n = mark_log
                break
            end
        end
        return true

    elseif tag == TAG_BETWEEN then
        local p, k, ts, te, le = token_mark(state)
        local mark_log = state.log_n
        if not run_token_emit(param, state, param.expr_a[expr_id]) or
           not run_token_emit(param, state, param.expr_b[expr_id]) or
           not run_token_emit(param, state, param.expr_c[expr_id]) then
            token_restore(state, p, k, ts, te, le)
            state.log_n = mark_log
            return false
        end
        return true

    elseif tag == TAG_SEP_BY then
        local item = param.expr_a[expr_id]
        local sep = param.expr_b[expr_id]
        local p, k, ts, te, le = token_mark(state)
        local mark_log = state.log_n
        if not run_token_emit(param, state, item) then
            token_restore(state, p, k, ts, te, le)
            state.log_n = mark_log
            return false
        end
        while true do
            local mp, mk, mts, mte, mle = token_mark(state)
            local mlog = state.log_n
            if not run_token_emit(param, state, sep) or not run_token_emit(param, state, item) then
                token_restore(state, mp, mk, mts, mte, mle)
                state.log_n = mlog
                break
            end
        end
        return true

    elseif tag == TAG_ASSOC then
        local p, k, ts, te, le = token_mark(state)
        local mark_log = state.log_n
        if not run_token_emit(param, state, param.expr_a[expr_id]) or
           not run_token_emit(param, state, param.expr_b[expr_id]) or
           not run_token_emit(param, state, param.expr_c[expr_id]) then
            token_restore(state, p, k, ts, te, le)
            state.log_n = mark_log
            return false
        end
        return true

    elseif tag == TAG_SEQ then
        local p, k, ts, te, le = token_mark(state)
        local mark_log = state.log_n
        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            if not run_token_emit(param, state, param.children[i]) then
                token_restore(state, p, k, ts, te, le)
                state.log_n = mark_log
                return false
            end
        end
        return true

    elseif tag == TAG_CHOICE then
        local chosen, predictive = token_choose_arm(param, state, expr_id)
        if predictive then
            if not chosen then return false end
            return run_token_emit(param, state, chosen)
        end

        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            local p, k, ts, te, le = token_mark(state)
            local mark_log = state.log_n
            if run_token_emit(param, state, param.children[i]) then return true end
            token_restore(state, p, k, ts, te, le)
            state.log_n = mark_log
        end
        return false
    end

    error("GPS.grammar: bad token-emit tag " .. tostring(tag), 2)
end

run_token_reduce = function(param, state, expr_id, actions, source)
    local tag = param.expr_tag[expr_id]
    local s = state.cursor

    if tag == TAG_EMPTY then
        return true, nil

    elseif tag == TAG_TOK then
        if s.tok_kind ~= param.expr_a[expr_id] then return false end
        local start_pos, stop_pos = s.tok_start, s.tok_stop
        s.last_end = stop_pos
        token_advance(param, state)
        return true, apply_token_action(actions, param.expr_name[expr_id], source, start_pos, stop_pos, state)

    elseif tag == TAG_REF then
        local rule_id = param.expr_a[expr_id]
        local start_pos = s.tok_start
        local ok, value = run_token_reduce(param, state, param.rule_expr[rule_id], actions, source)
        if not ok then return false end
        return true, apply_rule_action(actions, param.rule_name[rule_id], value, source, start_pos, state.cursor.last_end)

    elseif tag == TAG_OPTIONAL then
        local p, k, ts, te, le = token_mark(state)
        local ok, value = run_token_reduce(param, state, param.expr_a[expr_id], actions, source)
        if ok then return true, value end
        token_restore(state, p, k, ts, te, le)
        return true, nil

    elseif tag == TAG_ZERO_OR_MORE then
        local body = param.expr_a[expr_id]
        local out = {}
        while true do
            local p, k, ts, te, le = token_mark(state)
            local ok, value = run_token_reduce(param, state, body, actions, source)
            if not ok then
                token_restore(state, p, k, ts, te, le)
                break
            end
            if value ~= nil then out[#out + 1] = value end
        end
        return true, out

    elseif tag == TAG_ONE_OR_MORE then
        local body = param.expr_a[expr_id]
        local ok, first = run_token_reduce(param, state, body, actions, source)
        if not ok then return false end
        local out = {}
        if first ~= nil then out[#out + 1] = first end
        while true do
            local p, k, ts, te, le = token_mark(state)
            local next_ok, value = run_token_reduce(param, state, body, actions, source)
            if not next_ok then
                token_restore(state, p, k, ts, te, le)
                break
            end
            if value ~= nil then out[#out + 1] = value end
        end
        return true, out

    elseif tag == TAG_BETWEEN then
        local p, k, ts, te, le = token_mark(state)
        if not run_token_reduce(param, state, param.expr_a[expr_id], actions, source) then return false end
        local ok_body, body_value = run_token_reduce(param, state, param.expr_b[expr_id], actions, source)
        if not ok_body then token_restore(state, p, k, ts, te, le); return false end
        if not run_token_reduce(param, state, param.expr_c[expr_id], actions, source) then token_restore(state, p, k, ts, te, le); return false end
        return true, body_value

    elseif tag == TAG_SEP_BY then
        local item = param.expr_a[expr_id]
        local sep = param.expr_b[expr_id]
        local p, k, ts, te, le = token_mark(state)
        local ok, first = run_token_reduce(param, state, item, actions, source)
        if not ok then token_restore(state, p, k, ts, te, le); return false end
        local out = {}
        if first ~= nil then out[#out + 1] = first end
        while true do
            local mp, mk, mts, mte, mle = token_mark(state)
            if not run_token_reduce(param, state, sep, actions, source) then
                token_restore(state, mp, mk, mts, mte, mle)
                break
            end
            local ok_item, value = run_token_reduce(param, state, item, actions, source)
            if not ok_item then
                token_restore(state, mp, mk, mts, mte, mle)
                break
            end
            if value ~= nil then out[#out + 1] = value end
        end
        return true, out

    elseif tag == TAG_ASSOC then
        local p, k, ts, te, le = token_mark(state)
        local ok_key, key_value = run_token_reduce(param, state, param.expr_a[expr_id], actions, source)
        if not ok_key then return false end
        if not run_token_reduce(param, state, param.expr_b[expr_id], actions, source) then token_restore(state, p, k, ts, te, le); return false end
        local ok_val, val_value = run_token_reduce(param, state, param.expr_c[expr_id], actions, source)
        if not ok_val then token_restore(state, p, k, ts, te, le); return false end
        return true, { key_value, val_value }

    elseif tag == TAG_SEQ then
        local p, k, ts, te, le = token_mark(state)
        local result_mode = param.seq_result_mode[expr_id] or RESULT_ALL
        local keep_a = param.seq_result_a[expr_id]
        local keep_b = param.seq_result_b[expr_id]
        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1

        if result_mode == RESULT_INDEX then
            local kept = nil
            local rel = 1
            for i = lo, hi do
                local ok, value = run_token_reduce(param, state, param.children[i], actions, source)
                if not ok then
                    token_restore(state, p, k, ts, te, le)
                    return false
                end
                if rel == keep_a then kept = value end
                rel = rel + 1
            end
            return true, kept

        elseif result_mode == RESULT_PAIR then
            local va, vb = nil, nil
            local rel = 1
            for i = lo, hi do
                local ok, value = run_token_reduce(param, state, param.children[i], actions, source)
                if not ok then
                    token_restore(state, p, k, ts, te, le)
                    return false
                end
                if rel == keep_a then va = value elseif rel == keep_b then vb = value end
                rel = rel + 1
            end
            return true, { va, vb }

        else
            local out = {}
            for i = lo, hi do
                local ok, value = run_token_reduce(param, state, param.children[i], actions, source)
                if not ok then
                    token_restore(state, p, k, ts, te, le)
                    return false
                end
                if value ~= nil then out[#out + 1] = value end
            end
            return true, out
        end

    elseif tag == TAG_CHOICE then
        local chosen, predictive = token_choose_arm(param, state, expr_id)
        if predictive then
            if not chosen then return false end
            return run_token_reduce(param, state, chosen, actions, source)
        end

        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            local p, k, ts, te, le = token_mark(state)
            local ok, value = run_token_reduce(param, state, param.children[i], actions, source)
            if ok then return true, value end
            token_restore(state, p, k, ts, te, le)
        end
        return false
    end

    error("GPS.grammar: bad token-reduce tag " .. tostring(tag), 2)
end

local function direct_mark(state)
    return state.pos, state.last_end
end

local function direct_restore(state, pos, last_end)
    state.pos = pos
    state.last_end = last_end
end

local function direct_peek_key(param, state)
    local pos = skip_direct_input(param, state.input, state.pos)
    local input, len = state.input.input, state.input.len
    if pos >= len then return nil end
    local b = input[pos]
    if b == C_QUOTE then return "#str" end
    if b == C_MINUS or (b >= C_0 and b <= C_9) then return "#num" end
    return "#b" .. tostring(b)
end

local function direct_choose_arm(param, state, expr_id)
    local dispatch = param.choice_dispatch[expr_id]
    if not dispatch then return nil, false end
    local arm = dispatch[direct_peek_key(param, state)] or (param.choice_fallback[expr_id] ~= 0 and param.choice_fallback[expr_id] or nil)
    return arm, true
end

run_direct_match = function(param, state, expr_id, source)
    local tag = param.expr_tag[expr_id]

    if tag == TAG_EMPTY then
        return true

    elseif tag == TAG_LIT then
        local pos = skip_direct_input(param, state.input, state.pos)
        local text = param.expr_text[expr_id]
        if not match_str(state.input.input, state.input.len, pos, text) then return false end
        state.pos = pos + #text
        state.last_end = state.pos
        return true

    elseif tag == TAG_NUM then
        local pos = skip_direct_input(param, state.input, state.pos)
        local value, new_pos = parse_number_value(state.input, pos, source)
        if value == nil then return false end
        state.pos = new_pos
        state.last_end = new_pos
        return true

    elseif tag == TAG_STR then
        local pos = skip_direct_input(param, state.input, state.pos)
        local value, new_pos = parse_string_value(state.input, pos, source)
        if value == nil then return false end
        state.pos = new_pos
        state.last_end = new_pos
        return true

    elseif tag == TAG_REF then
        return run_direct_match(param, state, param.rule_expr[param.expr_a[expr_id]], source)

    elseif tag == TAG_OPTIONAL then
        local p, le = direct_mark(state)
        if run_direct_match(param, state, param.expr_a[expr_id], source) then return true end
        direct_restore(state, p, le)
        return true

    elseif tag == TAG_ZERO_OR_MORE then
        local body = param.expr_a[expr_id]
        while true do
            local p, le = direct_mark(state)
            if not run_direct_match(param, state, body, source) then
                direct_restore(state, p, le)
                break
            end
        end
        return true

    elseif tag == TAG_ONE_OR_MORE then
        local body = param.expr_a[expr_id]
        if not run_direct_match(param, state, body, source) then return false end
        while true do
            local p, le = direct_mark(state)
            if not run_direct_match(param, state, body, source) then
                direct_restore(state, p, le)
                break
            end
        end
        return true

    elseif tag == TAG_BETWEEN then
        local p, le = direct_mark(state)
        if not run_direct_match(param, state, param.expr_a[expr_id], source) or
           not run_direct_match(param, state, param.expr_b[expr_id], source) or
           not run_direct_match(param, state, param.expr_c[expr_id], source) then
            direct_restore(state, p, le)
            return false
        end
        return true

    elseif tag == TAG_SEP_BY then
        local item = param.expr_a[expr_id]
        local sep = param.expr_b[expr_id]
        local p, le = direct_mark(state)
        if not run_direct_match(param, state, item, source) then
            direct_restore(state, p, le)
            return false
        end
        while true do
            local mp, mle = direct_mark(state)
            if not run_direct_match(param, state, sep, source) or not run_direct_match(param, state, item, source) then
                direct_restore(state, mp, mle)
                break
            end
        end
        return true

    elseif tag == TAG_ASSOC then
        local p, le = direct_mark(state)
        if not run_direct_match(param, state, param.expr_a[expr_id], source) or
           not run_direct_match(param, state, param.expr_b[expr_id], source) or
           not run_direct_match(param, state, param.expr_c[expr_id], source) then
            direct_restore(state, p, le)
            return false
        end
        return true

    elseif tag == TAG_SEQ then
        local p, le = direct_mark(state)
        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            if not run_direct_match(param, state, param.children[i], source) then
                direct_restore(state, p, le)
                return false
            end
        end
        return true

    elseif tag == TAG_CHOICE then
        local chosen, predictive = direct_choose_arm(param, state, expr_id)
        if predictive then
            if not chosen then return false end
            return run_direct_match(param, state, chosen, source)
        end

        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            local p, le = direct_mark(state)
            if run_direct_match(param, state, param.children[i], source) then return true end
            direct_restore(state, p, le)
        end
        return false
    end

    error("GPS.grammar: bad direct-match tag " .. tostring(tag), 2)
end

run_direct_emit = function(param, state, expr_id, source)
    local tag = param.expr_tag[expr_id]

    if tag == TAG_EMPTY then
        return true

    elseif tag == TAG_LIT then
        local pos = skip_direct_input(param, state.input, state.pos)
        local text = param.expr_text[expr_id]
        if not match_str(state.input.input, state.input.len, pos, text) then return false end
        state.pos = pos + #text
        state.last_end = state.pos
        emit_log_token(state, param.expr_name[expr_id], pos, state.pos)
        return true

    elseif tag == TAG_NUM then
        local pos = skip_direct_input(param, state.input, state.pos)
        local value, new_pos = parse_number_value(state.input, pos, source)
        if value == nil then return false end
        state.pos = new_pos
        state.last_end = new_pos
        emit_log_token(state, param.expr_name[expr_id], pos, new_pos)
        return true

    elseif tag == TAG_STR then
        local pos = skip_direct_input(param, state.input, state.pos)
        local value, new_pos = parse_string_value(state.input, pos, source)
        if value == nil then return false end
        state.pos = new_pos
        state.last_end = new_pos
        emit_log_token(state, param.expr_name[expr_id], pos, new_pos)
        return true

    elseif tag == TAG_REF then
        local rule_id = param.expr_a[expr_id]
        local start_pos = skip_direct_input(param, state.input, state.pos)
        if not run_direct_emit(param, state, param.rule_expr[rule_id], source) then return false end
        emit_log_rule(state, param.rule_name[rule_id], start_pos, state.last_end)
        return true

    elseif tag == TAG_OPTIONAL then
        local p, le = direct_mark(state)
        local mark_log = state.log_n
        if run_direct_emit(param, state, param.expr_a[expr_id], source) then return true end
        direct_restore(state, p, le)
        state.log_n = mark_log
        return true

    elseif tag == TAG_ZERO_OR_MORE then
        local body = param.expr_a[expr_id]
        while true do
            local p, le = direct_mark(state)
            local mark_log = state.log_n
            if not run_direct_emit(param, state, body, source) then
                direct_restore(state, p, le)
                state.log_n = mark_log
                break
            end
        end
        return true

    elseif tag == TAG_ONE_OR_MORE then
        local body = param.expr_a[expr_id]
        if not run_direct_emit(param, state, body, source) then return false end
        while true do
            local p, le = direct_mark(state)
            local mark_log = state.log_n
            if not run_direct_emit(param, state, body, source) then
                direct_restore(state, p, le)
                state.log_n = mark_log
                break
            end
        end
        return true

    elseif tag == TAG_BETWEEN then
        local p, le = direct_mark(state)
        local mark_log = state.log_n
        if not run_direct_emit(param, state, param.expr_a[expr_id], source) or
           not run_direct_emit(param, state, param.expr_b[expr_id], source) or
           not run_direct_emit(param, state, param.expr_c[expr_id], source) then
            direct_restore(state, p, le)
            state.log_n = mark_log
            return false
        end
        return true

    elseif tag == TAG_SEP_BY then
        local item = param.expr_a[expr_id]
        local sep = param.expr_b[expr_id]
        local p, le = direct_mark(state)
        local mark_log = state.log_n
        if not run_direct_emit(param, state, item, source) then
            direct_restore(state, p, le)
            state.log_n = mark_log
            return false
        end
        while true do
            local mp, mle = direct_mark(state)
            local mlog = state.log_n
            if not run_direct_emit(param, state, sep, source) or not run_direct_emit(param, state, item, source) then
                direct_restore(state, mp, mle)
                state.log_n = mlog
                break
            end
        end
        return true

    elseif tag == TAG_ASSOC then
        local p, le = direct_mark(state)
        local mark_log = state.log_n
        if not run_direct_emit(param, state, param.expr_a[expr_id], source) or
           not run_direct_emit(param, state, param.expr_b[expr_id], source) or
           not run_direct_emit(param, state, param.expr_c[expr_id], source) then
            direct_restore(state, p, le)
            state.log_n = mark_log
            return false
        end
        return true

    elseif tag == TAG_SEQ then
        local p, le = direct_mark(state)
        local mark_log = state.log_n
        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            if not run_direct_emit(param, state, param.children[i], source) then
                direct_restore(state, p, le)
                state.log_n = mark_log
                return false
            end
        end
        return true

    elseif tag == TAG_CHOICE then
        local chosen, predictive = direct_choose_arm(param, state, expr_id)
        if predictive then
            if not chosen then return false end
            return run_direct_emit(param, state, chosen, source)
        end

        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            local p, le = direct_mark(state)
            local mark_log = state.log_n
            if run_direct_emit(param, state, param.children[i], source) then return true end
            direct_restore(state, p, le)
            state.log_n = mark_log
        end
        return false
    end

    error("GPS.grammar: bad direct-emit tag " .. tostring(tag), 2)
end

run_direct_reduce = function(param, state, expr_id, actions, source)
    local tag = param.expr_tag[expr_id]

    if tag == TAG_EMPTY then
        return true, nil

    elseif tag == TAG_LIT then
        local pos = skip_direct_input(param, state.input, state.pos)
        local text = param.expr_text[expr_id]
        if not match_str(state.input.input, state.input.len, pos, text) then return false end
        state.pos = pos + #text
        state.last_end = state.pos
        return true, apply_token_action(actions, param.expr_name[expr_id], source, pos, state.pos, state)

    elseif tag == TAG_NUM then
        local pos = skip_direct_input(param, state.input, state.pos)
        local value, new_pos = parse_number_value(state.input, pos, source)
        if value == nil then return false end
        state.pos = new_pos
        state.last_end = new_pos
        return true, apply_token_action(actions, param.expr_name[expr_id], source, pos, new_pos, state)

    elseif tag == TAG_STR then
        local pos = skip_direct_input(param, state.input, state.pos)
        local value, new_pos = parse_string_value(state.input, pos, source)
        if value == nil then return false end
        state.pos = new_pos
        state.last_end = new_pos
        return true, apply_token_action(actions, param.expr_name[expr_id], source, pos, new_pos, state)

    elseif tag == TAG_REF then
        local rule_id = param.expr_a[expr_id]
        local start_pos = skip_direct_input(param, state.input, state.pos)
        local ok, value = run_direct_reduce(param, state, param.rule_expr[rule_id], actions, source)
        if not ok then return false end
        return true, apply_rule_action(actions, param.rule_name[rule_id], value, source, start_pos, state.last_end)

    elseif tag == TAG_OPTIONAL then
        local p, le = direct_mark(state)
        local ok, value = run_direct_reduce(param, state, param.expr_a[expr_id], actions, source)
        if ok then return true, value end
        direct_restore(state, p, le)
        return true, nil

    elseif tag == TAG_ZERO_OR_MORE then
        local body = param.expr_a[expr_id]
        local out = {}
        while true do
            local p, le = direct_mark(state)
            local ok, value = run_direct_reduce(param, state, body, actions, source)
            if not ok then
                direct_restore(state, p, le)
                break
            end
            if value ~= nil then out[#out + 1] = value end
        end
        return true, out

    elseif tag == TAG_ONE_OR_MORE then
        local body = param.expr_a[expr_id]
        local ok, first = run_direct_reduce(param, state, body, actions, source)
        if not ok then return false end
        local out = {}
        if first ~= nil then out[#out + 1] = first end
        while true do
            local p, le = direct_mark(state)
            local next_ok, value = run_direct_reduce(param, state, body, actions, source)
            if not next_ok then
                direct_restore(state, p, le)
                break
            end
            if value ~= nil then out[#out + 1] = value end
        end
        return true, out

    elseif tag == TAG_BETWEEN then
        local p, le = direct_mark(state)
        if not run_direct_reduce(param, state, param.expr_a[expr_id], actions, source) then return false end
        local ok_body, body_value = run_direct_reduce(param, state, param.expr_b[expr_id], actions, source)
        if not ok_body then direct_restore(state, p, le); return false end
        if not run_direct_reduce(param, state, param.expr_c[expr_id], actions, source) then direct_restore(state, p, le); return false end
        return true, body_value

    elseif tag == TAG_SEP_BY then
        local item = param.expr_a[expr_id]
        local sep = param.expr_b[expr_id]
        local p, le = direct_mark(state)
        local ok, first = run_direct_reduce(param, state, item, actions, source)
        if not ok then direct_restore(state, p, le); return false end
        local out = {}
        if first ~= nil then out[#out + 1] = first end
        while true do
            local mp, mle = direct_mark(state)
            if not run_direct_reduce(param, state, sep, actions, source) then
                direct_restore(state, mp, mle)
                break
            end
            local ok_item, value = run_direct_reduce(param, state, item, actions, source)
            if not ok_item then
                direct_restore(state, mp, mle)
                break
            end
            if value ~= nil then out[#out + 1] = value end
        end
        return true, out

    elseif tag == TAG_ASSOC then
        local p, le = direct_mark(state)
        local ok_key, key_value = run_direct_reduce(param, state, param.expr_a[expr_id], actions, source)
        if not ok_key then return false end
        if not run_direct_reduce(param, state, param.expr_b[expr_id], actions, source) then direct_restore(state, p, le); return false end
        local ok_val, val_value = run_direct_reduce(param, state, param.expr_c[expr_id], actions, source)
        if not ok_val then direct_restore(state, p, le); return false end
        return true, { key_value, val_value }

    elseif tag == TAG_SEQ then
        local p, le = direct_mark(state)
        local result_mode = param.seq_result_mode[expr_id] or RESULT_ALL
        local keep_a = param.seq_result_a[expr_id]
        local keep_b = param.seq_result_b[expr_id]
        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1

        if result_mode == RESULT_INDEX then
            local kept = nil
            local rel = 1
            for i = lo, hi do
                local ok, value = run_direct_reduce(param, state, param.children[i], actions, source)
                if not ok then
                    direct_restore(state, p, le)
                    return false
                end
                if rel == keep_a then kept = value end
                rel = rel + 1
            end
            return true, kept

        elseif result_mode == RESULT_PAIR then
            local va, vb = nil, nil
            local rel = 1
            for i = lo, hi do
                local ok, value = run_direct_reduce(param, state, param.children[i], actions, source)
                if not ok then
                    direct_restore(state, p, le)
                    return false
                end
                if rel == keep_a then va = value elseif rel == keep_b then vb = value end
                rel = rel + 1
            end
            return true, { va, vb }

        else
            local out = {}
            for i = lo, hi do
                local ok, value = run_direct_reduce(param, state, param.children[i], actions, source)
                if not ok then
                    direct_restore(state, p, le)
                    return false
                end
                if value ~= nil then out[#out + 1] = value end
            end
            return true, out
        end

    elseif tag == TAG_CHOICE then
        local chosen, predictive = direct_choose_arm(param, state, expr_id)
        if predictive then
            if not chosen then return false end
            return run_direct_reduce(param, state, chosen, actions, source)
        end

        local lo = param.child_lo[expr_id]
        local hi = lo + param.child_len[expr_id] - 1
        for i = lo, hi do
            local p, le = direct_mark(state)
            local ok, value = run_direct_reduce(param, state, param.children[i], actions, source)
            if ok then return true, value end
            direct_restore(state, p, le)
        end
        return false
    end

    error("GPS.grammar: bad direct-reduce tag " .. tostring(tag), 2)
end

local function run_compiled(param, compiled_input, source, mode, aux)
    if param.mode == "token" then
        local state = new_token_state()
        reset_token_state(state, compiled_input)
        token_advance(param, state)

        if mode == MODE_MATCH then
            if not run_token_match(param, state, param.rule_expr[param.start_rule]) then return token_error(state, source) end
            if state.cursor.tok_kind ~= 0 then return token_error(state, source, "trailing input") end
            return true, true

        elseif mode == MODE_EMIT then
            local start_pos = state.cursor.tok_start
            if not run_token_emit(param, state, param.rule_expr[param.start_rule]) then return token_error(state, source) end
            emit_log_rule(state, param.rule_name[param.start_rule], start_pos, state.cursor.last_end)
            if state.cursor.tok_kind ~= 0 then return token_error(state, source, "trailing input") end
            return true, replay_emit_log(state, source, aux)

        elseif mode == MODE_REDUCE then
            local actions = normalize_actions(aux)
            local start_pos = state.cursor.tok_start
            local ok, value = run_token_reduce(param, state, param.rule_expr[param.start_rule], actions, source)
            if not ok then return token_error(state, source) end
            value = apply_rule_action(actions, param.rule_name[param.start_rule], value, source, start_pos, state.cursor.last_end)
            if state.cursor.tok_kind ~= 0 then return token_error(state, source, "trailing input") end
            return true, value
        end

    else
        local state = new_direct_state()
        reset_direct_state(state, compiled_input)

        if mode == MODE_MATCH then
            if not run_direct_match(param, state, param.rule_expr[param.start_rule], source) then return direct_error(param, state, source) end
            state.pos = skip_direct_input(param, state.input, state.pos)
            if state.pos ~= state.input.len then return direct_error(param, state, source, "trailing input") end
            return true, true

        elseif mode == MODE_EMIT then
            local start_pos = skip_direct_input(param, state.input, state.pos)
            if not run_direct_emit(param, state, param.rule_expr[param.start_rule], source) then return direct_error(param, state, source) end
            emit_log_rule(state, param.rule_name[param.start_rule], start_pos, state.last_end)
            state.pos = skip_direct_input(param, state.input, state.pos)
            if state.pos ~= state.input.len then return direct_error(param, state, source, "trailing input") end
            return true, replay_emit_log(state, source, aux)

        elseif mode == MODE_REDUCE then
            local actions = normalize_actions(aux)
            local start_pos = skip_direct_input(param, state.input, state.pos)
            local ok, value = run_direct_reduce(param, state, param.rule_expr[param.start_rule], actions, source)
            if not ok then return direct_error(param, state, source) end
            value = apply_rule_action(actions, param.rule_name[param.start_rule], value, source, start_pos, state.last_end)
            state.pos = skip_direct_input(param, state.input, state.pos)
            if state.pos ~= state.input.len then return direct_error(param, state, source, "trailing input") end
            return true, value
        end
    end

    error("GPS.grammar: bad executor mode", 2)
end

local function format_parse_error(value)
    return string.format("GPS.grammar parse error at %d near %q (%s)",
        value.pos or -1,
        value.text or "",
        value.message or value.token or "error")
end

function PARSER_MT:try_match(input_string)
    return run_compiled(self.param, self.param.compile_input(input_string), input_string, MODE_MATCH)
end

function PARSER_MT:match(input_string)
    local ok = self:try_match(input_string)
    return ok
end

function PARSER_MT:try_emit(input_string, sink)
    return run_compiled(self.param, self.param.compile_input(input_string), input_string, MODE_EMIT, sink)
end

function PARSER_MT:emit(input_string, sink)
    local ok, value = self:try_emit(input_string, sink)
    if not ok then error(format_parse_error(value), 2) end
    return value
end

function PARSER_MT:try_reduce(input_string, actions)
    return run_compiled(self.param, self.param.compile_input(input_string), input_string, MODE_REDUCE, actions)
end

function PARSER_MT:reduce(input_string, actions)
    local ok, value = self:try_reduce(input_string, actions)
    if not ok then error(format_parse_error(value), 2) end
    return value
end

function PARSER_MT:try_tree(input_string)
    return run_compiled(self.param, self.param.compile_input(input_string), input_string, MODE_REDUCE, TREE_ACTIONS)
end

function PARSER_MT:tree(input_string)
    local ok, value = self:try_tree(input_string)
    if not ok then error(format_parse_error(value), 2) end
    return value
end

PARSER_MT.parse = PARSER_MT.tree
PARSER_MT.try_parse = PARSER_MT.try_tree

function PARSER_MT:reducer(actions)
    local cache_key = actions or TREE_ACTIONS
    local cache = rawget(self, "_reducer_cache")
    local hit = cache and cache[cache_key]
    if hit then return hit end
    cache = cache or setmetatable({}, { __mode = "k" })
    rawset(self, "_reducer_cache", cache)
    local family = setmetatable({
        __gps_reducer = true,
        parser = self,
        actions = normalize_actions(actions),
        start = self.start,
        mode = self.mode,
    }, { __index = REDUCER_MT })
    cache[cache_key] = family
    return family
end

local function machine_match_gen(machine_param)
    local ok = run_compiled(machine_param.parser_param, machine_param.compiled_input, machine_param.source, MODE_MATCH)
    return ok
end

local function machine_emit_gen(machine_param)
    return run_compiled(machine_param.parser_param, machine_param.compiled_input, machine_param.source, MODE_EMIT, machine_param.sink)
end

local function machine_reduce_gen(machine_param)
    return run_compiled(machine_param.parser_param, machine_param.compiled_input, machine_param.source, MODE_REDUCE, machine_param.actions)
end

function PARSER_MT:machine(input_string, mode, arg)
    if not GPS or type(GPS.machine) ~= "function" then
        error("GPS.grammar: GPS.machine is not available", 2)
    end
    local compiled_input = self.param.compile_input(input_string)
    mode = mode or "match"
    if mode == "match" then
        return GPS.machine(machine_match_gen, {
            parser_param = self.param,
            compiled_input = compiled_input,
            source = input_string,
        }, GPS.EMPTY_STATE, self.start .. "|match")
    elseif mode == "emit" then
        return GPS.machine(machine_emit_gen, {
            parser_param = self.param,
            compiled_input = compiled_input,
            source = input_string,
            sink = arg,
        }, GPS.EMPTY_STATE, self.start .. "|emit")
    elseif mode == "tree" then
        return self:reducer(TREE_ACTIONS):machine(input_string)
    elseif mode == "reduce" then
        return self:reducer(arg):machine(input_string)
    end
    error("GPS.grammar: unknown machine mode '" .. tostring(mode) .. "'", 2)
end

function REDUCER_MT:try_parse(input_string)
    return run_compiled(self.parser.param, self.parser.param.compile_input(input_string), input_string, MODE_REDUCE, self.actions)
end

function REDUCER_MT:parse(input_string)
    local ok, value = self:try_parse(input_string)
    if not ok then error(format_parse_error(value), 2) end
    return value
end

function REDUCER_MT:machine(input_string)
    if not GPS or type(GPS.machine) ~= "function" then
        error("GPS.grammar: GPS.machine is not available", 2)
    end
    local compiled_input = self.parser.param.compile_input(input_string)
    return GPS.machine(machine_reduce_gen, {
        parser_param = self.parser.param,
        compiled_input = compiled_input,
        source = input_string,
        actions = self.actions,
    }, GPS.EMPTY_STATE, self.start .. "|reduce")
end

return function(GPS, asdl_context)
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
                 | Between(Expr open, Expr body, Expr close) unique
                 | SepBy(Expr item, Expr sep) unique
                 | Assoc(Expr key, Expr sep, Expr value) unique
                 | Ref(string name) unique
                 | Tok(string name) unique
                 | Lit(string text) unique
                 | Num
                 | Str
                 | Empty
        }
    ]]

    local CTX = asdl_context.NewContext():Define(GRAMMAR_SCHEMA)

    local function compile(spec)
        if not CTX.Grammar.Spec:isclassof(spec) then
            error("GPS.grammar: expected Grammar.Spec", 2)
        end
        local source_rule_map = get_rule_map(spec)
        if not source_rule_map[spec.parse.start] then
            error("GPS.grammar: unknown start rule '" .. tostring(spec.parse.start) .. "'", 2)
        end

        local parse_mode = detect_parse_mode(source_rule_map, spec.parse.start)
        local rule_map = lower_rule_map(source_rule_map)
        local lexer = nil
        if parse_mode == "token" then
            lexer = build_lexer(GPS, spec, collect_used_tokens(rule_map, spec.parse.start))
        end

        local param = flatten_grammar(rule_map, spec.parse.start, parse_mode, lexer, spec)
        return setmetatable({
            __gps_parser = true,
            param = param,
            lexer = lexer,
            rules = param.reachable,
            start = spec.parse.start,
            mode = parse_mode,
            Grammar = CTX.Grammar,
        }, { __index = PARSER_MT })
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
