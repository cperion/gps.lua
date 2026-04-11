-- gps/grammar2.lua — grammar compiler, rewritten for canonical flatness
--
-- Same as grammar.lua but with:
--   1. Unified executor: ONE recursive function instead of six
--   2. Input backends: token vs direct abstracted behind a backend table
--   3. Mode parameter: match / emit / reduce in one path
--   4. ~40% less code, zero duplication
--
-- Architecture (through the lens of GUIDE chapters 37-38):
--
--   Grammar ASDL (recursive Expr tree)
--     │
--     │  compile: lower_expr → flatten_grammar
--     │  ← the ONE tree walk; outputs flat integer-indexed arrays
--     ▼
--   Compiled param (flat tables: expr_tag[], expr_a[], children[], ...)
--     │
--     │  run: single recursive function over flat tables
--     │  ← recursion bounded by grammar depth (~20), not input size
--     ▼
--   Result (bool for match, log for emit, value for reduce)
--
-- Dependency cycle analysis:
--   Parent (rule) needs from child: success/fail, reduced value, first-set
--   Child needs from parent: nothing (just cursor position)
--   Cycles at runtime: 0 → one pass suffices
--   Cycles at compile time: 1 (first-set fixpoint) → resolved by iteration

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
    } Gps2TokenState;
]]
local TokenState = ffi.typeof("Gps2TokenState")

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════

local TAG_EMPTY        = 1
local TAG_TOK          = 2
local TAG_REF          = 3
local TAG_SEQ          = 4
local TAG_CHOICE       = 5
local TAG_OPTIONAL     = 6
local TAG_ZERO_OR_MORE = 7
local TAG_ONE_OR_MORE  = 8
local TAG_BETWEEN      = 9
local TAG_SEP_BY       = 10
local TAG_ASSOC        = 11
local TAG_LIT          = 12
local TAG_NUM          = 13
local TAG_STR          = 14

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
    [string.byte('n')]  = "\n",  [string.byte('r')]  = "\r",
    [string.byte('t')]  = "\t",  [string.byte('b')]  = "\b",
    [string.byte('f')]  = "\f",  [string.byte('"')]  = '"',
    [string.byte('\\')] = '\\',  [string.byte('/')]  = '/',
}

local EMPTY_ACTIONS = { tokens = {}, rules = {} }
local TREE_ACTIONS  = { __gps_tree_actions = true }

-- ═══════════════════════════════════════════════════════════════
-- SMALL HELPERS (shared with grammar.lua, unchanged)
-- ═══════════════════════════════════════════════════════════════

local function shallow_copy(t)
    local out = {}; for k, v in pairs(t) do out[k] = v end; return out
end

local function token_name(tok)
    return (tok.kind == "Symbol" or tok.kind == "Keyword") and tok.text or tok.name
end

local function get_rule_map(spec)
    local map = {}
    for i = 1, #spec.parse.rules do
        local r = spec.parse.rules[i]; map[r.name] = r
    end; return map
end

-- ═══════════════════════════════════════════════════════════════
-- EXPRESSION LOWERING (identical to grammar.lua)
-- ═══════════════════════════════════════════════════════════════

local function lower_expr(expr, memo)
    local hit = memo[expr]; if hit then return hit end
    local kind, out = expr.kind, nil

    if kind == "Between" then
        out = { kind = "Seq", items = {
            lower_expr(expr.open, memo), lower_expr(expr.body, memo), lower_expr(expr.close, memo),
        }, result_mode = RESULT_INDEX, result_a = 2 }
    elseif kind == "Assoc" then
        out = { kind = "Seq", items = {
            lower_expr(expr.key, memo), lower_expr(expr.sep, memo), lower_expr(expr.value, memo),
        }, result_mode = RESULT_PAIR, result_a = 1, result_b = 3 }
    elseif kind == "Seq" then
        local items = {}
        for i = 1, #expr.items do
            local c = lower_expr(expr.items[i], memo)
            if c.kind == "Seq" and (c.result_mode == nil or c.result_mode == RESULT_ALL) then
                for j = 1, #c.items do items[#items+1] = c.items[j] end
            else items[#items+1] = c end
        end
        out = { kind="Seq", items=items, result_mode=expr.result_mode or RESULT_ALL,
                result_a=expr.result_a, result_b=expr.result_b }
    elseif kind == "Choice" then
        local arms = {}
        for i = 1, #expr.arms do
            local c = lower_expr(expr.arms[i], memo)
            if c.kind == "Choice" then
                for j = 1, #c.arms do arms[#arms+1] = c.arms[j] end
            else arms[#arms+1] = c end
        end
        out = { kind="Choice", arms=arms }
    elseif kind == "Optional"    then out = { kind="Optional",    body = lower_expr(expr.body, memo) }
    elseif kind == "ZeroOrMore"  then out = { kind="ZeroOrMore",  body = lower_expr(expr.body, memo) }
    elseif kind == "OneOrMore"   then out = { kind="OneOrMore",   body = lower_expr(expr.body, memo) }
    elseif kind == "SepBy"       then out = { kind="SepBy", item = lower_expr(expr.item, memo), sep = lower_expr(expr.sep, memo) }
    else out = expr end
    memo[expr] = out; return out
end

local function lower_rule_map(rule_map)
    local memo, lo = {}, {}
    for name, rule in pairs(rule_map) do
        lo[name] = { name=rule.name, body=lower_expr(rule.body, memo) }
    end; return lo
end

-- ═══════════════════════════════════════════════════════════════
-- ANALYSIS: reachable rules, used tokens, nullable/first, left-recursion
-- (same logic as grammar.lua, compacted)
-- ═══════════════════════════════════════════════════════════════

local function walk_expr(expr, fn)
    fn(expr)
    local k = expr.kind
    if k == "Seq"    then for i=1,#expr.items do walk_expr(expr.items[i], fn) end
    elseif k == "Choice" then for i=1,#expr.arms do walk_expr(expr.arms[i], fn) end
    elseif k == "ZeroOrMore" or k == "OneOrMore" or k == "Optional" then walk_expr(expr.body, fn)
    elseif k == "SepBy" then walk_expr(expr.item, fn); walk_expr(expr.sep, fn)
    end
end

local function collect_reachable(rule_map, start)
    local seen, order = {}, {}
    local function visit(name)
        if seen[name] then return end
        local r = rule_map[name]
        if not r then error("GPS.grammar2: unknown rule '"..tostring(name).."'", 3) end
        seen[name] = true; order[#order+1] = r
        walk_expr(r.body, function(e) if e.kind == "Ref" then visit(e.name) end end)
    end
    visit(start); return seen, order
end

local function collect_used_tokens(rule_map, start)
    local used = {}
    local seen = {}
    local function visit(name)
        if seen[name] then return end; seen[name] = true
        walk_expr(rule_map[name].body, function(e)
            if e.kind == "Tok" then used[e.name] = true
            elseif e.kind == "Ref" then visit(e.name) end
        end)
    end
    visit(start); return used
end

local function collect_exprs(rule_order)
    local seen, out = {}, {}
    local function walk(e)
        if seen[e] then return end; seen[e] = true; out[#out+1] = e
        local k = e.kind
        if k == "Seq"    then for i=1,#e.items do walk(e.items[i]) end
        elseif k == "Choice" then for i=1,#e.arms do walk(e.arms[i]) end
        elseif k == "ZeroOrMore" or k == "OneOrMore" or k == "Optional" then walk(e.body)
        elseif k == "SepBy" then walk(e.item); walk(e.sep) end
    end
    for i = 1, #rule_order do walk(rule_order[i].body) end
    return out
end

local function expr_first_key(expr, token_ids, parse_mode)
    if parse_mode == "token" then
        return expr.kind == "Tok" and token_ids[expr.name] or nil
    end
    if expr.kind == "Lit" then return expr.text ~= "" and ("#b"..tostring(expr.text:byte(1))) or nil
    elseif expr.kind == "Num" then return "#num"
    elseif expr.kind == "Str" then return "#str" end
    return nil
end

local function compute_nullable_first(rule_map, rule_order, token_ids, parse_mode)
    local exprs = collect_exprs(rule_order)
    local info = {}
    for i = 1, #exprs do info[exprs[i]] = { nullable=false, first={} } end

    local function union(d, s)
        local ch = false; for k in pairs(s) do if not d[k] then d[k]=true; ch=true end end; return ch
    end

    local changed = true
    while changed do
        changed = false
        for i = 1, #exprs do
            local e = exprs[i]; local inf = info[e]; local k = e.kind

            if k == "Tok" or k == "Lit" or k == "Num" or k == "Str" then
                local key = expr_first_key(e, token_ids, parse_mode)
                if key and not inf.first[key] then inf.first[key]=true; changed=true end

            elseif k == "Ref" then
                local ri = info[rule_map[e.name].body]
                if union(inf.first, ri.first) then changed=true end
                if ri.nullable and not inf.nullable then inf.nullable=true; changed=true end

            elseif k == "Empty" then
                if not inf.nullable then inf.nullable=true; changed=true end

            elseif k == "Optional" or k == "ZeroOrMore" then
                if union(inf.first, info[e.body].first) then changed=true end
                if not inf.nullable then inf.nullable=true; changed=true end

            elseif k == "OneOrMore" then
                if union(inf.first, info[e.body].first) then changed=true end
                if info[e.body].nullable and not inf.nullable then inf.nullable=true; changed=true end

            elseif k == "Seq" then
                local all = true
                for j=1,#e.items do
                    if union(inf.first, info[e.items[j]].first) then changed=true end
                    if not info[e.items[j]].nullable then all=false; break end
                end
                if all and not inf.nullable then inf.nullable=true; changed=true end

            elseif k == "Choice" then
                local any = false
                for j=1,#e.arms do
                    if union(inf.first, info[e.arms[j]].first) then changed=true end
                    if info[e.arms[j]].nullable then any=true end
                end
                if any and not inf.nullable then inf.nullable=true; changed=true end

            elseif k == "SepBy" then
                if union(inf.first, info[e.item].first) then changed=true end
                if info[e.item].nullable and not inf.nullable then inf.nullable=true; changed=true end
            end
        end
    end

    -- validate
    for i = 1, #exprs do
        local e = exprs[i]
        if (e.kind == "ZeroOrMore" or e.kind == "OneOrMore") and info[e.body].nullable then
            error("GPS.grammar2: repetition body is nullable: "..e.kind, 3)
        end
        if e.kind == "SepBy" and info[e.item].nullable then
            error("GPS.grammar2: SepBy item is nullable", 3)
        end
    end
    return info
end

local function reject_left_recursion(rule_order, rule_map, info)
    local graph = {}
    for i = 1, #rule_order do
        local r = rule_order[i]; local refs = {}
        local function collect(e)
            if e.kind == "Ref" then refs[e.name] = true
            elseif e.kind == "Seq" then
                for j=1,#e.items do collect(e.items[j]); if not info[e.items[j]].nullable then break end end
            elseif e.kind == "Choice" then for j=1,#e.arms do collect(e.arms[j]) end
            elseif e.kind == "ZeroOrMore" or e.kind == "OneOrMore" or e.kind == "Optional" then collect(e.body)
            elseif e.kind == "SepBy" then collect(e.item) end
        end
        collect(r.body); graph[r.name] = refs
    end
    local visiting, done = {}, {}
    local function visit(name)
        if done[name] then return end
        if visiting[name] then error("GPS.grammar2: left recursion through '"..name.."'", 3) end
        visiting[name] = true
        for ref in pairs(graph[name] or {}) do visit(ref) end
        visiting[name] = nil; done[name] = true
    end
    for i = 1, #rule_order do visit(rule_order[i].name) end
end

local function detect_parse_mode(rule_map, start)
    local _, order = collect_reachable(rule_map, start)
    local exprs = collect_exprs(order)
    local has_tok, has_direct = false, false
    for i = 1, #exprs do
        local k = exprs[i].kind
        if k == "Tok" then has_tok = true end
        if k == "Lit" or k == "Num" or k == "Str" then has_direct = true end
    end
    if has_tok and has_direct then
        error("GPS.grammar2: cannot mix Tok with Lit/Num/Str", 2)
    end
    return has_tok and "token" or "direct"
end

-- ═══════════════════════════════════════════════════════════════
-- LEXER BUILDER (same as grammar.lua)
-- ═══════════════════════════════════════════════════════════════

local function build_lexer(GPS, spec, used)
    local syms, kws = {}, {}
    local ls = { whitespace = false }
    local saw_i, saw_n, saw_s = false, false, false
    for i = 1, #spec.lex.tokens do
        local t = spec.lex.tokens[i]; local name = token_name(t)
        if used[name] then
            if t.kind == "Symbol"  then syms[#syms+1] = t.text
            elseif t.kind == "Keyword" then kws[#kws+1] = t.text
            elseif t.kind == "Ident"   then ls.ident = true; saw_i = true
            elseif t.kind == "Number"  then ls.number = true; saw_n = true
            elseif t.kind == "String"  then ls.string_quote = t.quote; saw_s = true end
        end
    end
    for i = 1, #spec.lex.skip do
        local s = spec.lex.skip[i]
        if s.kind == "Whitespace" then ls.whitespace = true
        elseif s.kind == "LineComment" then ls.line_comment = s.open
        elseif s.kind == "BlockComment" then ls.block_comment = { s.open, s.close } end
    end
    if #syms > 0 then ls.symbols = table.concat(syms, " ") end
    if #kws > 0 then ls.keywords = kws end
    return GPS.lex(ls)
end

-- ═══════════════════════════════════════════════════════════════
-- FLATTEN GRAMMAR → PARALLEL ARRAYS (same structure as grammar.lua)
-- ═══════════════════════════════════════════════════════════════

local function flatten_grammar(rule_map, start, parse_mode, lexer, spec)
    local reachable, rule_order = collect_reachable(rule_map, start)
    local token_ids = lexer and lexer.TOKEN or nil
    local info = compute_nullable_first(rule_map, rule_order, token_ids, parse_mode)
    reject_left_recursion(rule_order, rule_map, info)

    local exprs = collect_exprs(rule_order)
    local eid = {}; for i=1,#exprs do eid[exprs[i]] = i end

    local rid, rname, rexpr = {}, {}, {}
    for i=1,#rule_order do
        local r = rule_order[i]; rid[r.name]=i; rname[i]=r.name; rexpr[i]=eid[r.body]
    end

    local etag, ea, eb, ec = {}, {}, {}, {}
    local clo, clen, children = {}, {}, {}
    local cdisp, cfb = {}, {}
    local ename, etext = {}, {}
    local srm, sra, srb = {}, {}, {}

    local function append_ch(list)
        local lo = #children+1
        for i=1,#list do children[#children+1] = eid[list[i]] end
        return lo, #list
    end

    for i = 1, #exprs do
        local e = exprs[i]; local k = e.kind

        if k == "Empty"       then etag[i] = TAG_EMPTY
        elseif k == "Tok"     then etag[i]=TAG_TOK; ea[i]=token_ids[e.name]; ename[i]=e.name
        elseif k == "Ref"     then etag[i]=TAG_REF; ea[i]=rid[e.name]
        elseif k == "Lit"     then etag[i]=TAG_LIT; etext[i]=e.text; ename[i]=e.text
        elseif k == "Num"     then etag[i]=TAG_NUM; ename[i]="NUMBER"
        elseif k == "Str"     then etag[i]=TAG_STR; ename[i]="STRING"
        elseif k == "Optional"    then etag[i]=TAG_OPTIONAL;     ea[i]=eid[e.body]
        elseif k == "ZeroOrMore"  then etag[i]=TAG_ZERO_OR_MORE; ea[i]=eid[e.body]
        elseif k == "OneOrMore"   then etag[i]=TAG_ONE_OR_MORE;  ea[i]=eid[e.body]
        elseif k == "SepBy"       then etag[i]=TAG_SEP_BY; ea[i]=eid[e.item]; eb[i]=eid[e.sep]
        elseif k == "Seq" then
            etag[i]=TAG_SEQ; clo[i],clen[i]=append_ch(e.items)
            srm[i]=e.result_mode or RESULT_ALL; sra[i]=e.result_a or 0; srb[i]=e.result_b or 0
        elseif k == "Choice" then
            etag[i]=TAG_CHOICE; clo[i],clen[i]=append_ch(e.arms)
            -- predictive dispatch
            local ok, dispatch, fallback = true, {}, 0
            for j=1,#e.arms do
                local a = e.arms[j]; local ai = eid[a]; local ainf = info[a]
                if ainf.nullable then
                    if fallback ~= 0 then ok=false; break end; fallback = ai
                end
                for key in pairs(ainf.first) do
                    if dispatch[key] and dispatch[key] ~= ai then ok=false; break end
                    dispatch[key] = ai
                end
                if not ok then break end
            end
            if ok then cdisp[i]=dispatch; cfb[i]=fallback end
        end
    end

    return {
        mode = parse_mode,
        start_rule = rid[start], start_name = start,
        rname=rname, rexpr=rexpr,
        etag=etag, ea=ea, eb=eb, ec=ec,
        clo=clo, clen=clen, children=children,
        cdisp=cdisp, cfb=cfb,
        ename=ename, etext=etext,
        srm=srm, sra=sra, srb=srb,
        lexer = lexer,
        reachable = reachable,
        skip_defs = parse_mode == "direct" and (function()
            local out = {}
            for i=1,#spec.lex.skip do
                local s = spec.lex.skip[i]
                if s.kind=="Whitespace" then out[#out+1]={kind="Whitespace"}
                elseif s.kind=="LineComment" then out[#out+1]={kind="LineComment",open=s.open}
                elseif s.kind=="BlockComment" then out[#out+1]={kind="BlockComment",open=s.open,close=s.close} end
            end; return out
        end)() or nil,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- SHARED TERMINAL HELPERS
-- ═══════════════════════════════════════════════════════════════

local function match_str_bytes(input, len, pos, str)
    if pos + #str > len then return false end
    for i = 0, #str-1 do if input[pos+i] ~= str:byte(i+1) then return false end end
    return true
end

local function is_space(b) return b==32 or b==9 or b==10 or b==13 end

-- ═══════════════════════════════════════════════════════════════
-- ACTIONS
-- ═══════════════════════════════════════════════════════════════

local function normalize_actions(a)
    if a == TREE_ACTIONS then return a end
    if not a then return EMPTY_ACTIONS end
    if a.__gps_normalized then return a end
    return { __gps_normalized=true, raw=a,
             tokens = a.tokens or a.token or EMPTY_ACTIONS.tokens,
             rules  = a.rules  or a.rule  or EMPTY_ACTIONS.rules }
end

local function apply_tok_action(actions, name, source, st, sp, runtime)
    if actions == TREE_ACTIONS then
        return { kind=name, text=source:sub(st+1,sp), start=st, stop=sp }
    end
    local a = actions.tokens[name]
    if a ~= nil then return type(a)=="function" and a(source,st,sp,name,runtime) or a end
    return source:sub(st+1, sp)
end

local function apply_rule_action(actions, name, val, source, st, sp)
    if actions == TREE_ACTIONS then
        return { kind=name, value=val, start=st, stop=sp }
    end
    local a = actions.rules[name]
    if a ~= nil then return a(val, source, st, sp, name) end
    return val
end

-- ═══════════════════════════════════════════════════════════════
-- UNIFIED EXECUTOR — one function, three modes, two backends
--
-- Instead of method calls through a backend object (which LuaJIT can't
-- inline), we generate the executor at parse time with backend ops as
-- direct upvalue closures. Two generators: token mode and direct mode.
-- Each produces a run_full(P, input_string, mode, aux) closure.
-- ═══════════════════════════════════════════════════════════════

local function replay_log(ln, lk, lname, lst, lsp, source, sink)
    if not sink then return ln end
    local on_tok = sink.token or sink.on_token
    local on_rule = sink.rule or sink.on_rule
    for i = 1, ln do
        if lk[i] == 1 then
            if on_tok then on_tok(sink, lname[i], source, lst[i], lsp[i]) end
        else
            if on_rule then on_rule(sink, lname[i], source, lst[i], lsp[i]) end
        end
    end; return ln
end

-- ── Token-mode executor generator ────────────────────────────

local function make_token_runner(P)
    local lex_next = P.lexer.lex_next
    local compile_input = P.lexer.compile

    return function(_, input_string, mode, aux)
        local compiled = compile_input(input_string)
        local source = input_string

        -- cursor state (direct locals, no table indirection)
        local s = ffi.new(TokenState)
        s.pos=0; s.tok_kind=-1; s.tok_start=0; s.tok_stop=0; s.last_end=0
        local function advance()
            local np,k,st,sp = lex_next(compiled, s.pos)
            if np==nil then s.tok_kind=0; s.tok_start=s.pos; s.tok_stop=s.pos
            else s.pos=np; s.tok_kind=k; s.tok_start=st; s.tok_stop=sp end
        end
        advance()

        -- emit log
        local ln,lk,lname,lst,lsp = 0,{},{},{},{}
        -- reduce
        local actions = mode == MODE_REDUCE and normalize_actions(aux) or nil

        local run -- forward
        run = function(eid)
            local tag = P.etag[eid]
            if tag == TAG_EMPTY then return true, nil
            elseif tag == TAG_TOK then
                if s.tok_kind ~= P.ea[eid] then return false end
                local st,sp = s.tok_start, s.tok_stop; s.last_end=sp; advance()
                local name = P.ename[eid]
                if mode==MODE_EMIT then ln=ln+1; lk[ln]=1; lname[ln]=name; lst[ln]=st; lsp[ln]=sp
                elseif mode==MODE_REDUCE then return true, apply_tok_action(actions,name,source,st,sp) end
                return true, nil

            elseif tag == TAG_LIT or tag == TAG_NUM or tag == TAG_STR then
                return false -- not used in token mode

            elseif tag == TAG_REF then
                local rid = P.ea[eid]; local st = s.tok_start
                local ok,val = run(P.rexpr[rid])
                if not ok then return false end
                local name = P.rname[rid]
                if mode==MODE_EMIT then ln=ln+1; lk[ln]=2; lname[ln]=name; lst[ln]=st; lsp[ln]=s.last_end
                elseif mode==MODE_REDUCE then return true, apply_rule_action(actions,name,val,source,st,s.last_end) end
                return true, nil

            elseif tag == TAG_OPTIONAL then
                local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local ln0=ln
                local ok,val = run(P.ea[eid])
                if ok then return true, val end
                s.pos=p0; s.tok_kind=k0; s.tok_start=ts0; s.tok_stop=te0; s.last_end=le0; ln=ln0
                return true, nil

            elseif tag == TAG_ZERO_OR_MORE then
                local body = P.ea[eid]
                if mode==MODE_REDUCE then
                    local out = {}
                    while true do
                        local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end
                        local ok,val = run(body)
                        if not ok then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0; break end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                else
                    while true do
                        local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local ln0=ln
                        if not run(body) then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0;ln=ln0; break end
                    end; return true, nil
                end

            elseif tag == TAG_ONE_OR_MORE then
                local body = P.ea[eid]
                if mode==MODE_REDUCE then
                    local ok,first = run(body); if not ok then return false end
                    local out = {}; if first~=nil then out[1]=first end
                    while true do
                        local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end
                        local ok2,val = run(body)
                        if not ok2 then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0; break end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                else
                    if not run(body) then return false end
                    while true do
                        local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local ln0=ln
                        if not run(body) then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0;ln=ln0; break end
                    end; return true, nil
                end

            elseif tag == TAG_SEP_BY then
                local item,sep = P.ea[eid], P.eb[eid]
                if mode==MODE_REDUCE then
                    local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end
                    local ok,first = run(item); if not ok then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0; return false end
                    local out = {}; if first~=nil then out[1]=first end
                    while true do
                        local mp,mk,mts,mte,mle = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end
                        if not run(sep) then s.pos=mp;s.tok_kind=mk;s.tok_start=mts;s.tok_stop=mte;s.last_end=mle; break end
                        local ok2,val = run(item)
                        if not ok2 then s.pos=mp;s.tok_kind=mk;s.tok_start=mts;s.tok_stop=mte;s.last_end=mle; break end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                else
                    local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local ln0=ln
                    if not run(item) then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0;ln=ln0; return false end
                    while true do
                        local mp,mk,mts,mte,mle = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local mln=ln
                        if not run(sep) or not run(item) then s.pos=mp;s.tok_kind=mk;s.tok_start=mts;s.tok_stop=mte;s.last_end=mle;ln=mln; break end
                    end; return true, nil
                end

            elseif tag == TAG_SEQ then
                local lo = P.clo[eid]; local hi = lo + P.clen[eid] - 1
                local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local ln0=ln
                if mode~=MODE_REDUCE then
                    for i=lo,hi do
                        if not run(P.children[i]) then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0;ln=ln0; return false end
                    end; return true, nil
                end
                local rm = P.srm[eid] or RESULT_ALL
                if rm==RESULT_INDEX then
                    local kept,rel,ka = nil,1,P.sra[eid]
                    for i=lo,hi do
                        local ok,val = run(P.children[i])
                        if not ok then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0; return false end
                        if rel==ka then kept=val end; rel=rel+1
                    end; return true, kept
                elseif rm==RESULT_PAIR then
                    local va,vb,rel,ka,kb = nil,nil,1,P.sra[eid],P.srb[eid]
                    for i=lo,hi do
                        local ok,val = run(P.children[i])
                        if not ok then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0; return false end
                        if rel==ka then va=val elseif rel==kb then vb=val end; rel=rel+1
                    end; return true, {va,vb}
                else
                    local out = {}
                    for i=lo,hi do
                        local ok,val = run(P.children[i])
                        if not ok then s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0; return false end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                end

            elseif tag == TAG_CHOICE then
                local disp = P.cdisp[eid]
                if disp then
                    local chosen = disp[s.tok_kind] or (P.cfb[eid]~=0 and P.cfb[eid] or nil)
                    if not chosen then return false end
                    return run(chosen)
                end
                local lo = P.clo[eid]; local hi = lo + P.clen[eid] - 1
                for i=lo,hi do
                    local p0,k0,ts0,te0,le0 = s.pos,s.tok_kind,s.tok_start,s.tok_stop,s.last_end; local ln0=ln
                    local ok,val = run(P.children[i])
                    if ok then return true, val end
                    s.pos=p0;s.tok_kind=k0;s.tok_start=ts0;s.tok_stop=te0;s.last_end=le0;ln=ln0
                end; return false
            end
            error("GPS.grammar2: unknown tag "..tostring(tag), 2)
        end

        -- entry point
        local start_eid = P.rexpr[P.start_rule]
        if mode==MODE_MATCH then
            if not run(start_eid) then
                return false, {pos=s.tok_start,text=source:sub(s.tok_start+1,math.min(#source,s.tok_stop+16)),message="parse error"}
            end
            if s.tok_kind~=0 then return false, {pos=s.tok_start,text=source:sub(s.tok_start+1,math.min(#source,s.tok_stop+16)),message="trailing input"} end
            return true, true
        elseif mode==MODE_EMIT then
            local st = s.tok_start
            if not run(start_eid) then
                return false, {pos=s.tok_start,text=source:sub(s.tok_start+1,math.min(#source,s.tok_stop+16)),message="parse error"}
            end
            ln=ln+1; lk[ln]=2; lname[ln]=P.rname[P.start_rule]; lst[ln]=st; lsp[ln]=s.last_end
            if s.tok_kind~=0 then return false, {pos=s.tok_start,text=source:sub(s.tok_start+1,math.min(#source,s.tok_stop+16)),message="trailing input"} end
            return true, replay_log(ln,lk,lname,lst,lsp,source,aux)
        elseif mode==MODE_REDUCE then
            local st = s.tok_start
            local ok,val = run(start_eid)
            if not ok then return false, {pos=s.tok_start,text=source:sub(s.tok_start+1,math.min(#source,s.tok_stop+16)),message="parse error"} end
            val = apply_rule_action(actions, P.rname[P.start_rule], val, source, st, s.last_end)
            if s.tok_kind~=0 then return false, {pos=s.tok_start,text=source:sub(s.tok_start+1,math.min(#source,s.tok_stop+16)),message="trailing input"} end
            return true, val
        end
    end
end

-- ── Direct-mode executor generator ───────────────────────────

local function compile_direct_input(s)
    local len=#s; local buf=ffi.new("uint8_t[?]",len); ffi.copy(buf,s,len)
    return {input=buf,len=len,source=s}
end

local function make_direct_runner(P)
    local skip_defs = P.skip_defs or {}

    return function(_, input_string, mode, aux)
        local compiled = compile_direct_input(input_string)
        local source = input_string
        local inp_buf, inp_len = compiled.input, compiled.len

        -- cursor (direct locals)
        local pos, last_end = 0, 0

        local function skip()
            while pos < inp_len do
                local adv = false
                for i=1,#skip_defs do
                    local sd = skip_defs[i]
                    if sd.kind=="Whitespace" then
                        if is_space(inp_buf[pos]) then
                            pos=pos+1; while pos<inp_len and is_space(inp_buf[pos]) do pos=pos+1 end; adv=true; break
                        end
                    elseif sd.kind=="LineComment" then
                        if match_str_bytes(inp_buf,inp_len,pos,sd.open) then
                            pos=pos+#sd.open; while pos<inp_len and inp_buf[pos]~=10 do pos=pos+1 end
                            if pos<inp_len then pos=pos+1 end; adv=true; break
                        end
                    elseif sd.kind=="BlockComment" then
                        if match_str_bytes(inp_buf,inp_len,pos,sd.open) then
                            pos=pos+#sd.open
                            while pos<inp_len do
                                if match_str_bytes(inp_buf,inp_len,pos,sd.close) then pos=pos+#sd.close; break end
                                pos=pos+1
                            end; adv=true; break
                        end
                    end
                end
                if not adv then break end
            end
        end

        -- inline number/string parsers (same as grammar.lua)
        local function parse_num()
            skip(); local sp=pos
            if pos<inp_len and inp_buf[pos]==C_MINUS then pos=pos+1 end
            if pos<inp_len and inp_buf[pos]==C_0 then pos=pos+1
            elseif pos<inp_len and inp_buf[pos]>C_0 and inp_buf[pos]<=C_9 then
                while pos<inp_len and inp_buf[pos]>=C_0 and inp_buf[pos]<=C_9 do pos=pos+1 end
            else pos=sp; return nil end
            if pos<inp_len and inp_buf[pos]==C_DOT then
                pos=pos+1; if pos>=inp_len or inp_buf[pos]<C_0 or inp_buf[pos]>C_9 then pos=sp; return nil end
                while pos<inp_len and inp_buf[pos]>=C_0 and inp_buf[pos]<=C_9 do pos=pos+1 end
            end
            if pos<inp_len and (inp_buf[pos]==C_e or inp_buf[pos]==C_E) then
                pos=pos+1; if pos<inp_len and (inp_buf[pos]==C_PLUS or inp_buf[pos]==C_MINUS) then pos=pos+1 end
                if pos>=inp_len or inp_buf[pos]<C_0 or inp_buf[pos]>C_9 then pos=sp; return nil end
                while pos<inp_len and inp_buf[pos]>=C_0 and inp_buf[pos]<=C_9 do pos=pos+1 end
            end
            return tonumber(sub(source,sp+1,pos))
        end

        local function parse_str()
            skip()
            if pos>=inp_len or inp_buf[pos]~=C_QUOTE then return nil end
            pos=pos+1; local sp=pos; local has_esc=false
            while pos<inp_len do
                local c=inp_buf[pos]
                if c==C_QUOTE then
                    if not has_esc then local v=sub(source,sp+1,pos); pos=pos+1; return v end; break
                elseif c==C_BSLASH then has_esc=true; pos=pos+2
                else pos=pos+1 end
            end
            if has_esc then
                pos=sp; local parts={}; local ps=pos
                while pos<inp_len do
                    local c=inp_buf[pos]
                    if c==C_QUOTE then
                        if pos>ps then parts[#parts+1]=sub(source,ps+1,pos) end; pos=pos+1; return concat(parts)
                    elseif c==C_BSLASH then
                        if pos>ps then parts[#parts+1]=sub(source,ps+1,pos) end
                        pos=pos+1; if pos>=inp_len then return nil end
                        local esc=inp_buf[pos]
                        if esc==C_u then
                            if pos+4>=inp_len then return nil end
                            local hx=sub(source,pos+2,pos+5); local code=tonumber(hx,16)
                            if not code then return nil end
                            if code<128 then parts[#parts+1]=char(code)
                            elseif code<2048 then parts[#parts+1]=char(192+math.floor(code/64),128+code%64)
                            else parts[#parts+1]=char(224+math.floor(code/4096),128+math.floor(code/64)%64,128+code%64) end
                            pos=pos+5
                        else parts[#parts+1]=ESCAPES[esc] or char(esc); pos=pos+1 end; ps=pos
                    else pos=pos+1 end
                end
            end; return nil
        end

        local function peek_key()
            skip(); if pos>=inp_len then return nil end
            local b=inp_buf[pos]
            if b==C_QUOTE then return "#str" end
            if b==C_MINUS or (b>=C_0 and b<=C_9) then return "#num" end
            return "#b"..tostring(b)
        end

        local function make_error(msg)
            skip(); return false, {pos=pos,text=source:sub(pos+1,math.min(#source,pos+16)),message=msg or "parse error"}
        end

        -- emit log
        local ln,lk,lname,lst,lsp = 0,{},{},{},{}
        local actions = mode==MODE_REDUCE and normalize_actions(aux) or nil

        local run
        run = function(eid)
            local tag = P.etag[eid]
            if tag == TAG_EMPTY then return true, nil

            elseif tag == TAG_LIT then
                skip()
                local text = P.etext[eid]
                if not match_str_bytes(inp_buf,inp_len,pos,text) then return false end
                local sp=pos; pos=pos+#text; last_end=pos
                local name=P.ename[eid]
                if mode==MODE_EMIT then ln=ln+1;lk[ln]=1;lname[ln]=name;lst[ln]=sp;lsp[ln]=pos
                elseif mode==MODE_REDUCE then return true,apply_tok_action(actions,name,source,sp,pos) end
                return true, nil

            elseif tag == TAG_NUM then
                skip(); local sp=pos
                local val=parse_num()
                if val==nil then return false end
                last_end=pos; local name=P.ename[eid]
                if mode==MODE_EMIT then ln=ln+1;lk[ln]=1;lname[ln]=name;lst[ln]=sp;lsp[ln]=pos
                elseif mode==MODE_REDUCE then return true,apply_tok_action(actions,name,source,sp,pos) end
                return true, nil

            elseif tag == TAG_STR then
                skip(); local sp=pos
                local val=parse_str()
                if val==nil then return false end
                last_end=pos; local name=P.ename[eid]
                if mode==MODE_EMIT then ln=ln+1;lk[ln]=1;lname[ln]=name;lst[ln]=sp;lsp[ln]=pos
                elseif mode==MODE_REDUCE then return true,apply_tok_action(actions,name,source,sp,pos) end
                return true, nil

            elseif tag == TAG_TOK then return false -- not used in direct mode

            elseif tag == TAG_REF then
                local rid=P.ea[eid]; skip(); local st=pos
                local ok,val = run(P.rexpr[rid])
                if not ok then return false end
                local name=P.rname[rid]
                if mode==MODE_EMIT then ln=ln+1;lk[ln]=2;lname[ln]=name;lst[ln]=st;lsp[ln]=last_end
                elseif mode==MODE_REDUCE then return true,apply_rule_action(actions,name,val,source,st,last_end) end
                return true, nil

            elseif tag == TAG_OPTIONAL then
                local p0,le0 = pos,last_end; local ln0=ln
                local ok,val = run(P.ea[eid])
                if ok then return true, val end
                pos=p0; last_end=le0; ln=ln0; return true, nil

            elseif tag == TAG_ZERO_OR_MORE then
                local body = P.ea[eid]
                if mode==MODE_REDUCE then
                    local out = {}
                    while true do
                        local p0,le0=pos,last_end
                        local ok,val=run(body)
                        if not ok then pos=p0;last_end=le0; break end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                else
                    while true do
                        local p0,le0=pos,last_end; local ln0=ln
                        if not run(body) then pos=p0;last_end=le0;ln=ln0; break end
                    end; return true, nil
                end

            elseif tag == TAG_ONE_OR_MORE then
                local body = P.ea[eid]
                if mode==MODE_REDUCE then
                    local ok,first = run(body); if not ok then return false end
                    local out = {}; if first~=nil then out[1]=first end
                    while true do
                        local p0,le0=pos,last_end
                        local ok2,val=run(body)
                        if not ok2 then pos=p0;last_end=le0; break end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                else
                    if not run(body) then return false end
                    while true do
                        local p0,le0=pos,last_end; local ln0=ln
                        if not run(body) then pos=p0;last_end=le0;ln=ln0; break end
                    end; return true, nil
                end

            elseif tag == TAG_SEP_BY then
                local item,sep = P.ea[eid],P.eb[eid]
                if mode==MODE_REDUCE then
                    local p0,le0=pos,last_end
                    local ok,first = run(item); if not ok then pos=p0;last_end=le0; return false end
                    local out = {}; if first~=nil then out[1]=first end
                    while true do
                        local mp,mle=pos,last_end
                        if not run(sep) then pos=mp;last_end=mle; break end
                        local ok2,val = run(item)
                        if not ok2 then pos=mp;last_end=mle; break end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                else
                    local p0,le0=pos,last_end; local ln0=ln
                    if not run(item) then pos=p0;last_end=le0;ln=ln0; return false end
                    while true do
                        local mp,mle=pos,last_end; local mln=ln
                        if not run(sep) or not run(item) then pos=mp;last_end=mle;ln=mln; break end
                    end; return true, nil
                end

            elseif tag == TAG_SEQ then
                local lo=P.clo[eid]; local hi=lo+P.clen[eid]-1
                local p0,le0=pos,last_end; local ln0=ln
                if mode~=MODE_REDUCE then
                    for i=lo,hi do if not run(P.children[i]) then pos=p0;last_end=le0;ln=ln0; return false end end
                    return true, nil
                end
                local rm=P.srm[eid] or RESULT_ALL
                if rm==RESULT_INDEX then
                    local kept,rel,ka=nil,1,P.sra[eid]
                    for i=lo,hi do
                        local ok,val=run(P.children[i])
                        if not ok then pos=p0;last_end=le0; return false end
                        if rel==ka then kept=val end; rel=rel+1
                    end; return true, kept
                elseif rm==RESULT_PAIR then
                    local va,vb,rel,ka,kb=nil,nil,1,P.sra[eid],P.srb[eid]
                    for i=lo,hi do
                        local ok,val=run(P.children[i])
                        if not ok then pos=p0;last_end=le0; return false end
                        if rel==ka then va=val elseif rel==kb then vb=val end; rel=rel+1
                    end; return true, {va,vb}
                else
                    local out={}
                    for i=lo,hi do
                        local ok,val=run(P.children[i])
                        if not ok then pos=p0;last_end=le0; return false end
                        if val~=nil then out[#out+1]=val end
                    end; return true, out
                end

            elseif tag == TAG_CHOICE then
                local disp=P.cdisp[eid]
                if disp then
                    local chosen=disp[peek_key()] or (P.cfb[eid]~=0 and P.cfb[eid] or nil)
                    if not chosen then return false end
                    return run(chosen)
                end
                local lo=P.clo[eid]; local hi=lo+P.clen[eid]-1
                for i=lo,hi do
                    local p0,le0=pos,last_end; local ln0=ln
                    local ok,val = run(P.children[i])
                    if ok then return true, val end
                    pos=p0;last_end=le0;ln=ln0
                end; return false
            end
            error("GPS.grammar2: unknown tag "..tostring(tag), 2)
        end

        local start_eid = P.rexpr[P.start_rule]
        if mode==MODE_MATCH then
            if not run(start_eid) then return make_error() end
            skip(); if pos~=inp_len then return make_error("trailing input") end
            return true, true
        elseif mode==MODE_EMIT then
            skip(); local st=pos
            if not run(start_eid) then return make_error() end
            ln=ln+1;lk[ln]=2;lname[ln]=P.rname[P.start_rule];lst[ln]=st;lsp[ln]=last_end
            skip(); if pos~=inp_len then return make_error("trailing input") end
            return true, replay_log(ln,lk,lname,lst,lsp,source,aux)
        elseif mode==MODE_REDUCE then
            skip(); local st=pos
            local ok,val = run(start_eid)
            if not ok then return make_error() end
            val = apply_rule_action(actions, P.rname[P.start_rule], val, source, st, last_end)
            skip(); if pos~=inp_len then return make_error("trailing input") end
            return true, val
        end
    end
end

-- ── Factory: pick the right runner at compile time ───────────

local function make_runner(P)
    if P.mode == "token" then return make_token_runner(P)
    else return make_direct_runner(P) end
end

local function run_full(P, input_string, mode, aux)
    return P._runner(nil, input_string, mode, aux)
end

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC API (same interface as grammar.lua)
-- ═══════════════════════════════════════════════════════════════

local PARSER_MT = {}
local REDUCER_MT = {}

local function fmt_err(v)
    return string.format("GPS.grammar2 parse error at %d near %q (%s)",
        v.pos or -1, v.text or "", v.message or "error")
end

function PARSER_MT:try_match(s)  return run_full(self.param, s, MODE_MATCH) end
function PARSER_MT:match(s)      return (self:try_match(s)) end
function PARSER_MT:try_emit(s, sink) return run_full(self.param, s, MODE_EMIT, sink) end
function PARSER_MT:emit(s, sink)
    local ok, v = self:try_emit(s, sink); if not ok then error(fmt_err(v), 2) end; return v
end
function PARSER_MT:try_reduce(s, a) return run_full(self.param, s, MODE_REDUCE, a) end
function PARSER_MT:reduce(s, a)
    local ok, v = self:try_reduce(s, a); if not ok then error(fmt_err(v), 2) end; return v
end
function PARSER_MT:try_tree(s) return run_full(self.param, s, MODE_REDUCE, TREE_ACTIONS) end
function PARSER_MT:tree(s)
    local ok, v = self:try_tree(s); if not ok then error(fmt_err(v), 2) end; return v
end
PARSER_MT.parse = PARSER_MT.tree
PARSER_MT.try_parse = PARSER_MT.try_tree

function PARSER_MT:reducer(actions)
    local cache = rawget(self, "_rc"); local key = actions or TREE_ACTIONS
    local hit = cache and cache[key]; if hit then return hit end
    cache = cache or setmetatable({}, {__mode="k"}); rawset(self, "_rc", cache)
    local fam = setmetatable({
        __gps_reducer=true, parser=self, actions=normalize_actions(actions), start=self.start, mode=self.mode,
    }, {__index=REDUCER_MT})
    cache[key] = fam; return fam
end

function REDUCER_MT:try_parse(s)
    return run_full(self.parser.param, s, MODE_REDUCE, self.actions)
end
function REDUCER_MT:parse(s)
    local ok, v = self:try_parse(s); if not ok then error(fmt_err(v), 2) end; return v
end

-- machine() compat stubs (require GPS.machine which may not exist yet)
function PARSER_MT:machine(input_string, mode_name, arg)
    if not GPS or type(GPS.machine) ~= "function" then
        error("GPS.grammar2: GPS.machine not available", 2)
    end
    if mode_name == "tree" then return self:reducer(TREE_ACTIONS):machine(input_string) end
    if mode_name == "reduce" then return self:reducer(arg):machine(input_string) end
    local compiled = (self.param.mode == "token" and self.param.lexer.compile or
        function(s) local l=#s; local b=ffi.new("uint8_t[?]",l); ffi.copy(b,s,l); return {input=b,len=l,source=s} end)(input_string)
    local m = mode_name == "emit" and MODE_EMIT or MODE_MATCH
    local gen = function(mp) return run_full(mp.P, mp.src, mp.m, mp.aux) end
    return GPS.machine(gen, { P=self.param, src=input_string, m=m, aux=arg }, GPS.EMPTY_STATE, self.start.."|"..tostring(mode_name))
end

function REDUCER_MT:machine(input_string)
    if not GPS or type(GPS.machine) ~= "function" then
        error("GPS.grammar2: GPS.machine not available", 2)
    end
    local gen = function(mp) return run_full(mp.P, mp.src, MODE_REDUCE, mp.actions) end
    return GPS.machine(gen, { P=self.parser.param, src=input_string, actions=self.actions }, GPS.EMPTY_STATE, self.start.."|reduce")
end

-- ═══════════════════════════════════════════════════════════════
-- MODULE ENTRY (same factory shape as grammar.lua)
-- ═══════════════════════════════════════════════════════════════

return function(GPS_ref, asdl_context)
    GPS = GPS_ref -- capture for machine() stubs

    local SCHEMA = [[
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

    local CTX = asdl_context.NewContext():Define(SCHEMA)

    local function compile(spec)
        -- Accept specs from any Grammar ASDL instance (duck-type check)
        if type(spec) ~= "table" or not spec.lex or not spec.parse then
            error("GPS.grammar2: expected Grammar.Spec (table with .lex and .parse)", 2)
        end
        local src_rules = get_rule_map(spec)
        if not src_rules[spec.parse.start] then error("GPS.grammar2: unknown start '"..spec.parse.start.."'", 2) end
        local pm = detect_parse_mode(src_rules, spec.parse.start)
        local rules = lower_rule_map(src_rules)
        local lexer = pm == "token" and build_lexer(GPS_ref, spec, collect_used_tokens(rules, spec.parse.start)) or nil
        local param = flatten_grammar(rules, spec.parse.start, pm, lexer, spec)
        param._runner = make_runner(param)
        return setmetatable({
            __gps_parser=true, param=param, lexer=lexer,
            rules=param.reachable, start=spec.parse.start, mode=pm, Grammar=CTX.Grammar,
        }, {__index=PARSER_MT})
    end

    local Api = {}
    function Api.context() return CTX end
    function Api.schema()  return SCHEMA end
    function Api.compile(spec) return compile(spec) end
    function Api.new()
        return setmetatable({Grammar=CTX.Grammar}, {
            __index = function(_, k) return Api[k] or CTX.Grammar[k] end,
        })
    end

    return setmetatable(Api, {
        __call = function(_, spec)
            if spec == nil then return Api.new() end
            return compile(spec)
        end,
    })
end
