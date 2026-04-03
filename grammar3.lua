-- grammar3.lua — grammar compiler, ugps architecture
--
-- Architecture:
--   Grammar ASDL tree (recursive Expr nodes)
--     → M.lower(): one tree walk (the ONE recursive pass)
--     → flat opcode array (parallel arrays: op[], a[], b[], name[])
--     → VM: one while-loop with ip, three explicit stacks
--
-- Recursion classes consumed:
--   Layer 1 (compile): grammar structure (Seq/Choice/Ref nesting)
--   Layer 2 (execute): backtracking + value composition
--   Both resolved in one flat opcode array with three stacks:
--     - call stack (rule Call/Ret)
--     - backtrack stack (Choice/Commit/Fail)
--     - value stack (reduce mode: terminal values → collected arrays → rule results)
--
-- No recursive executor. No 6× duplication. One loop. Three stacks.

local ffi = require("ffi")
local sub = string.sub
local char = string.char
local concat = table.concat

local M_framework -- set at module init

-- ═══════════════════════════════════════════════════════════════
-- OPCODES
-- ═══════════════════════════════════════════════════════════════

local OP_END             = 1
local OP_MATCH_TOK       = 2   -- a=tok_id, name=token_name
local OP_MATCH_LIT       = 3   -- name=literal_text
local OP_MATCH_NUM       = 4   -- name="NUMBER"
local OP_MATCH_STR       = 5   -- name="STRING"
local OP_CALL            = 6   -- a=addr, name=rule_name
local OP_RET             = 7
local OP_CHOICE          = 8   -- a=fail_addr
local OP_COMMIT          = 9   -- a=jump_addr
local OP_PARTIAL_COMMIT  = 10  -- a=jump_addr (for repetition)
local OP_FAIL            = 11
local OP_JUMP            = 12  -- a=addr
local OP_DISPATCH        = 13  -- a=default_addr, dispatch_table in aux
-- value ops (reduce mode)
local OP_PUSH_MARK       = 14
local OP_PACK_ALL        = 15
local OP_PACK_INDEX      = 16  -- a=index
local OP_PACK_PAIR       = 17  -- a=idx_a, b=idx_b
local OP_APPLY_TOKEN     = 18  -- name=token_name
local OP_APPLY_RULE      = 19  -- name=rule_name
local OP_PUSH_NIL        = 20

local OP_NAMES = {
    "END","MATCH_TOK","MATCH_LIT","MATCH_NUM","MATCH_STR",
    "CALL","RET","CHOICE","COMMIT","PARTIAL_COMMIT","FAIL",
    "JUMP","DISPATCH","PUSH_MARK","PACK_ALL","PACK_INDEX",
    "PACK_PAIR","APPLY_TOKEN","APPLY_RULE","PUSH_NIL",
}

-- ═══════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════

local MODE_MATCH  = 1
local MODE_EMIT   = 2
local MODE_REDUCE = 3

local RESULT_ALL   = 1
local RESULT_INDEX = 2
local RESULT_PAIR  = 3

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
    [string.byte('n')]="\n", [string.byte('r')]="\r", [string.byte('t')]="\t",
    [string.byte('b')]="\b", [string.byte('f')]="\f", [string.byte('"')]='"',
    [string.byte('\\')]='\\', [string.byte('/')]='/',
}

local EMPTY_ACTIONS = { tokens = {}, rules = {} }
local TREE_ACTIONS  = { __gps_tree_actions = true }

-- ═══════════════════════════════════════════════════════════════
-- ANALYSIS (compact: lower, nullable/first, left-recursion, lexer)
-- Reused from grammar2.lua — same logic, compacted
-- ═══════════════════════════════════════════════════════════════

local function token_name(tok)
    return (tok.kind == "Symbol" or tok.kind == "Keyword") and tok.text or tok.name
end

local function get_rule_map(spec)
    local m = {}; for i = 1, #spec.parse.rules do local r = spec.parse.rules[i]; m[r.name] = r end; return m
end

local function lower_expr(expr, memo)
    local hit = memo[expr]; if hit then return hit end
    local k, out = expr.kind, nil
    if k == "Between" then
        out = { kind="Seq", items={lower_expr(expr.open,memo), lower_expr(expr.body,memo), lower_expr(expr.close,memo)},
                result_mode=RESULT_INDEX, result_a=2 }
    elseif k == "Assoc" then
        out = { kind="Seq", items={lower_expr(expr.key,memo), lower_expr(expr.sep,memo), lower_expr(expr.value,memo)},
                result_mode=RESULT_PAIR, result_a=1, result_b=3 }
    elseif k == "Seq" then
        local items = {}
        for i = 1, #expr.items do
            local c = lower_expr(expr.items[i], memo)
            if c.kind == "Seq" and (c.result_mode == nil or c.result_mode == RESULT_ALL) then
                for j = 1, #c.items do items[#items+1] = c.items[j] end
            else items[#items+1] = c end
        end
        out = { kind="Seq", items=items, result_mode=expr.result_mode or RESULT_ALL,
                result_a=expr.result_a, result_b=expr.result_b }
    elseif k == "Choice" then
        local arms = {}
        for i = 1, #expr.arms do
            local c = lower_expr(expr.arms[i], memo)
            if c.kind == "Choice" then for j = 1, #c.arms do arms[#arms+1] = c.arms[j] end
            else arms[#arms+1] = c end
        end
        out = { kind="Choice", arms=arms }
    elseif k == "Optional"   then out = { kind="Optional",   body=lower_expr(expr.body,memo) }
    elseif k == "ZeroOrMore" then out = { kind="ZeroOrMore", body=lower_expr(expr.body,memo) }
    elseif k == "OneOrMore"  then out = { kind="OneOrMore",  body=lower_expr(expr.body,memo) }
    elseif k == "SepBy"      then out = { kind="SepBy", item=lower_expr(expr.item,memo), sep=lower_expr(expr.sep,memo) }
    else out = expr end
    memo[expr] = out; return out
end

local function lower_rule_map(rm)
    local memo, lo = {}, {}
    for n, r in pairs(rm) do lo[n] = { name=r.name, body=lower_expr(r.body, memo) } end; return lo
end

local function walk_expr(e, fn)
    fn(e); local k = e.kind
    if k == "Seq" then for i=1,#e.items do walk_expr(e.items[i],fn) end
    elseif k == "Choice" then for i=1,#e.arms do walk_expr(e.arms[i],fn) end
    elseif k == "ZeroOrMore" or k == "OneOrMore" or k == "Optional" then walk_expr(e.body,fn)
    elseif k == "SepBy" then walk_expr(e.item,fn); walk_expr(e.sep,fn) end
end

local function collect_reachable(rm, start)
    local seen, order = {}, {}
    local function visit(n)
        if seen[n] then return end
        local r = rm[n]; if not r then error("grammar3: unknown rule '"..n.."'", 3) end
        seen[n] = true; order[#order+1] = r
        walk_expr(r.body, function(e) if e.kind == "Ref" then visit(e.name) end end)
    end
    visit(start); return seen, order
end

local function collect_used_tokens(rm, start)
    local used, seen = {}, {}
    local function visit(n)
        if seen[n] then return end; seen[n] = true
        walk_expr(rm[n].body, function(e)
            if e.kind == "Tok" then used[e.name] = true
            elseif e.kind == "Ref" then visit(e.name) end
        end)
    end; visit(start); return used
end

local function collect_exprs(rule_order)
    local seen, out = {}, {}
    local function w(e)
        if seen[e] then return end; seen[e] = true; out[#out+1] = e
        local k = e.kind
        if k == "Seq" then for i=1,#e.items do w(e.items[i]) end
        elseif k == "Choice" then for i=1,#e.arms do w(e.arms[i]) end
        elseif k == "ZeroOrMore" or k == "OneOrMore" or k == "Optional" then w(e.body)
        elseif k == "SepBy" then w(e.item); w(e.sep) end
    end
    for i = 1, #rule_order do w(rule_order[i].body) end; return out
end

local function expr_first_key(e, tids, pm)
    if pm == "token" then return e.kind == "Tok" and tids[e.name] or nil end
    if e.kind == "Lit" then
        return e.text ~= "" and ("#b" .. tostring(e.text:byte(1))) or nil
    elseif e.kind == "Str" then
        return "#b" .. tostring(C_QUOTE)
    end
    return nil
end

local function compute_nullable_first(rm, ro, tids, pm)
    local exprs = collect_exprs(ro)
    local info = {}; for i=1,#exprs do info[exprs[i]] = { nullable=false, first={} } end
    local function union(d,s) local ch=false; for k in pairs(s) do if not d[k] then d[k]=true;ch=true end end; return ch end
    local changed = true
    while changed do
        changed = false
        for i = 1, #exprs do
            local e = exprs[i]; local inf = info[e]; local k = e.kind
            if k=="Tok" or k=="Lit" or k=="Str" then
                local key = expr_first_key(e,tids,pm)
                if key and not inf.first[key] then inf.first[key]=true; changed=true end
            elseif k=="Num" then
                if pm == "token" then
                    local key = expr_first_key(e, tids, pm)
                    if key and not inf.first[key] then inf.first[key]=true; changed=true end
                else
                    if not inf.first["#b" .. tostring(C_MINUS)] then inf.first["#b" .. tostring(C_MINUS)] = true; changed = true end
                    for b = C_0, C_9 do
                        local key = "#b" .. tostring(b)
                        if not inf.first[key] then inf.first[key] = true; changed = true end
                    end
                end
            elseif k=="Ref" then
                local ri = info[rm[e.name].body]
                if union(inf.first, ri.first) then changed=true end
                if ri.nullable and not inf.nullable then inf.nullable=true; changed=true end
            elseif k=="Empty" then
                if not inf.nullable then inf.nullable=true; changed=true end
            elseif k=="Optional" or k=="ZeroOrMore" then
                if union(inf.first, info[e.body].first) then changed=true end
                if not inf.nullable then inf.nullable=true; changed=true end
            elseif k=="OneOrMore" then
                if union(inf.first, info[e.body].first) then changed=true end
                if info[e.body].nullable and not inf.nullable then inf.nullable=true; changed=true end
            elseif k=="Seq" then
                local all=true
                for j=1,#e.items do
                    if union(inf.first, info[e.items[j]].first) then changed=true end
                    if not info[e.items[j]].nullable then all=false; break end
                end
                if all and not inf.nullable then inf.nullable=true; changed=true end
            elseif k=="Choice" then
                local any=false
                for j=1,#e.arms do
                    if union(inf.first, info[e.arms[j]].first) then changed=true end
                    if info[e.arms[j]].nullable then any=true end
                end
                if any and not inf.nullable then inf.nullable=true; changed=true end
            elseif k=="SepBy" then
                if union(inf.first, info[e.item].first) then changed=true end
                if info[e.item].nullable and not inf.nullable then inf.nullable=true; changed=true end
            end
        end
    end
    for i=1,#exprs do
        local e=exprs[i]
        if (e.kind=="ZeroOrMore" or e.kind=="OneOrMore") and info[e.body].nullable then
            error("grammar3: repetition body nullable",3) end
        if e.kind=="SepBy" and info[e.item].nullable then error("grammar3: SepBy item nullable",3) end
    end
    return info
end

local function reject_left_recursion(ro, rm, info)
    local graph = {}
    for i=1,#ro do
        local r=ro[i]; local refs={}
        local function collect(e)
            if e.kind=="Ref" then refs[e.name]=true
            elseif e.kind=="Seq" then
                for j=1,#e.items do collect(e.items[j]); if not info[e.items[j]].nullable then break end end
            elseif e.kind=="Choice" then for j=1,#e.arms do collect(e.arms[j]) end
            elseif e.kind=="ZeroOrMore" or e.kind=="OneOrMore" or e.kind=="Optional" then collect(e.body)
            elseif e.kind=="SepBy" then collect(e.item) end
        end
        collect(r.body); graph[r.name]=refs
    end
    local visiting,done={},{}
    local function visit(n)
        if done[n] then return end
        if visiting[n] then error("grammar3: left recursion '"..n.."'",3) end
        visiting[n]=true; for ref in pairs(graph[n] or {}) do visit(ref) end
        visiting[n]=nil; done[n]=true
    end
    for i=1,#ro do visit(ro[i].name) end
end

local function detect_parse_mode(rm, start)
    local _,order = collect_reachable(rm, start)
    local exprs = collect_exprs(order)
    local has_tok, has_direct = false, false
    for i=1,#exprs do
        local k = exprs[i].kind
        if k=="Tok" then has_tok=true end
        if k=="Lit" or k=="Num" or k=="Str" then has_direct=true end
    end
    if has_tok and has_direct then error("grammar3: cannot mix Tok with Lit/Num/Str",2) end
    return has_tok and "token" or "direct"
end

local function build_lexer(GPS, spec, used)
    local syms, kws = {}, {}
    local ls = { whitespace=false }
    for i=1,#spec.lex.tokens do
        local t=spec.lex.tokens[i]; local n=token_name(t)
        if used[n] then
            if t.kind=="Symbol" then syms[#syms+1]=t.text
            elseif t.kind=="Keyword" then kws[#kws+1]=t.text
            elseif t.kind=="Ident" then ls.ident=true
            elseif t.kind=="Number" then ls.number=true
            elseif t.kind=="String" then ls.string_quote=t.quote end
        end
    end
    for i=1,#spec.lex.skip do
        local s=spec.lex.skip[i]
        if s.kind=="Whitespace" then ls.whitespace=true
        elseif s.kind=="LineComment" then ls.line_comment=s.open
        elseif s.kind=="BlockComment" then ls.block_comment={s.open,s.close} end
    end
    if #syms>0 then ls.symbols=table.concat(syms," ") end
    if #kws>0 then ls.keywords=kws end
    return GPS.lex(ls)
end

-- ═══════════════════════════════════════════════════════════════
-- OPCODE COMPILER — grammar tree → flat opcode array
-- The ONE recursive pass. After this, everything is flat.
-- ═══════════════════════════════════════════════════════════════

local function compile_opcodes(rule_map, start, parse_mode, lexer, spec, info)
    local _, rule_order = collect_reachable(rule_map, start)
    local token_ids = lexer and lexer.TOKEN or nil

    -- parallel arrays (the flat opcode array)
    local op, oa, ob, oname, oaux = {}, {}, {}, {}, {}
    local n = 0

    local function emit(tag, a, b, name, aux)
        n = n + 1; op[n] = tag; oa[n] = a or 0; ob[n] = b or 0; oname[n] = name; oaux[n] = aux
        return n
    end

    local function patch(addr, new_a) oa[addr] = new_a end

    -- compile rules: assign addresses, then compile bodies
    local rule_addr = {}
    local rule_name_list = {}
    for i = 1, #rule_order do rule_name_list[i] = rule_order[i].name end

    -- two-pass: first compile all rule bodies sequentially
    -- rules are called by CALL(addr), return by RET

    local function compile_expr(e, reduce)
        local k = e.kind

        if k == "Empty" then
            -- nothing

        elseif k == "Tok" then
            emit(OP_MATCH_TOK, token_ids[e.name], 0, e.name)
            if reduce then emit(OP_APPLY_TOKEN, 0, 0, e.name) end

        elseif k == "Lit" then
            emit(OP_MATCH_LIT, 0, 0, e.text)
            if reduce then emit(OP_APPLY_TOKEN, 0, 0, e.text) end

        elseif k == "Num" then
            emit(OP_MATCH_NUM, 0, 0, "NUMBER")
            if reduce then emit(OP_APPLY_TOKEN, 0, 0, "NUMBER") end

        elseif k == "Str" then
            emit(OP_MATCH_STR, 0, 0, "STRING")
            if reduce then emit(OP_APPLY_TOKEN, 0, 0, "STRING") end

        elseif k == "Ref" then
            emit(OP_CALL, 0, 0, e.name) -- addr patched later
            local call_pc = n
            -- patch deferred until rule addresses are known
            oaux[call_pc] = e.name -- tag for patching
            if reduce then emit(OP_APPLY_RULE, 0, 0, e.name) end

        elseif k == "Seq" then
            local rm = e.result_mode or RESULT_ALL
            if reduce then
                if rm == RESULT_INDEX then emit(OP_PUSH_MARK)
                elseif rm == RESULT_PAIR then emit(OP_PUSH_MARK)
                elseif #e.items > 1 then emit(OP_PUSH_MARK) end
            end
            for i = 1, #e.items do compile_expr(e.items[i], reduce) end
            if reduce then
                if rm == RESULT_INDEX then emit(OP_PACK_INDEX, e.result_a)
                elseif rm == RESULT_PAIR then emit(OP_PACK_PAIR, e.result_a, e.result_b)
                elseif #e.items > 1 then emit(OP_PACK_ALL)
                -- single item: value already on stack, no pack needed
                end
            end

        elseif k == "Choice" then
            -- check for predictive dispatch
            local predictive = true
            local dispatch = {}
            local fallback_idx = nil
            for i = 1, #e.arms do
                local arm = e.arms[i]; local arm_info = info[arm]
                if arm_info.nullable then
                    if fallback_idx then predictive = false; break end
                    fallback_idx = i
                end
                for key in pairs(arm_info.first) do
                    if dispatch[key] and dispatch[key] ~= i then predictive = false; break end
                    dispatch[key] = i
                end
                if not predictive then break end
            end

            if predictive then
                -- emit DISPATCH + arm bodies + JUMPs to done
                local dispatch_pc = emit(OP_DISPATCH, 0, 0, nil, {}) -- aux = dispatch table, patched
                local arm_addrs = {}
                local jump_to_done = {}
                for i = 1, #e.arms do
                    arm_addrs[i] = n + 1
                    compile_expr(e.arms[i], reduce)
                    jump_to_done[#jump_to_done+1] = emit(OP_JUMP, 0) -- patched
                end
                local fail_addr = n + 1
                emit(OP_FAIL) -- if dispatch misses entirely
                local done = n + 1

                -- patch jumps
                for _, jpc in ipairs(jump_to_done) do patch(jpc, done) end

                -- build dispatch table: key → address
                local dtable = {}
                for key, arm_idx in pairs(dispatch) do dtable[key] = arm_addrs[arm_idx] end
                local default = fallback_idx and arm_addrs[fallback_idx] or fail_addr
                patch(dispatch_pc, default)
                oaux[dispatch_pc] = dtable
            else
                -- backtracking choice
                local commits = {}
                for i = 1, #e.arms do
                    if i < #e.arms then
                        local choice_pc = emit(OP_CHOICE, 0) -- fail_addr patched
                        compile_expr(e.arms[i], reduce)
                        commits[#commits+1] = emit(OP_COMMIT, 0) -- done_addr patched
                        patch(choice_pc, n + 1) -- fail → next arm
                    else
                        compile_expr(e.arms[i], reduce) -- last arm, no choice wrapper
                    end
                end
                local done = n + 1
                for _, cpc in ipairs(commits) do patch(cpc, done) end
            end

        elseif k == "Optional" then
            local choice_pc = emit(OP_CHOICE, 0)
            compile_expr(e.body, reduce)
            local commit_pc = emit(OP_COMMIT, 0)
            patch(choice_pc, n + 1) -- fail → skip
            if reduce then emit(OP_PUSH_NIL) end -- no match → nil value
            local skip = n + 1
            patch(commit_pc, skip)
            -- on match: value already on stack from body

        elseif k == "ZeroOrMore" then
            if reduce then emit(OP_PUSH_MARK) end
            local choice_pc = emit(OP_CHOICE, 0)
            local body_pc = n + 1
            compile_expr(e.body, reduce)
            emit(OP_PARTIAL_COMMIT, body_pc)
            patch(choice_pc, n + 1) -- fail → done
            if reduce then emit(OP_PACK_ALL) end

        elseif k == "OneOrMore" then
            if reduce then emit(OP_PUSH_MARK) end
            compile_expr(e.body, reduce) -- must match at least once
            local choice_pc = emit(OP_CHOICE, 0)
            local body_pc = n + 1
            compile_expr(e.body, reduce)
            emit(OP_PARTIAL_COMMIT, body_pc)
            patch(choice_pc, n + 1) -- fail → done
            if reduce then emit(OP_PACK_ALL) end

        elseif k == "SepBy" then
            -- One-or-more separated list:
            --   item (sep item)*
            if reduce then emit(OP_PUSH_MARK) end

            local outer_choice = emit(OP_CHOICE, 0)
            compile_expr(e.item, reduce)

            local inner_choice = emit(OP_CHOICE, 0)
            local loop_body = n + 1
            compile_expr(e.sep, false) -- separator never contributes a value
            compile_expr(e.item, reduce)
            emit(OP_PARTIAL_COMMIT, loop_body)

            local loop_done = n + 1
            local success_commit = emit(OP_COMMIT, 0)
            local fail_addr = n + 1
            emit(OP_FAIL)
            local exit_addr = n + 1
            if reduce then emit(OP_PACK_ALL) end

            patch(inner_choice, loop_done)      -- stop loop, keep accumulated items
            patch(outer_choice, fail_addr)      -- no first item: SepBy fails
            patch(success_commit, exit_addr)    -- one-or-more items: skip FAIL path

        else
            error("grammar3: unsupported expr kind '"..tostring(k).."'", 2)
        end
    end

    -- compile each rule body
    for i = 1, #rule_order do
        local r = rule_order[i]
        rule_addr[r.name] = n + 1
    end

    -- actually emit: need to know addresses, so compile in order and record starts
    local actual_addrs = {}
    for i = 1, #rule_order do
        local r = rule_order[i]
        actual_addrs[r.name] = n + 1
        compile_expr(r.body, true) -- always compile with reduce ops (they're skipped at runtime if mode ~= reduce)
        emit(OP_RET)
    end

    emit(OP_END)

    -- patch CALL addresses
    for pc = 1, n do
        if op[pc] == OP_CALL then
            local rname = oaux[pc]
            if type(rname) == "string" then
                oa[pc] = actual_addrs[rname]
                if not oa[pc] then error("grammar3: unresolved rule '"..rname.."'", 2) end
            end
        end
    end

    return {
        op = op, a = oa, b = ob, name = oname, aux = oaux,
        n = n,
        start_addr = actual_addrs[start],
        rule_addrs = actual_addrs,
        start_name = start,
        parse_mode = parse_mode,
        lexer = lexer,
        skip_defs = parse_mode == "direct" and (function()
            local out = {}
            for i=1,#spec.lex.skip do
                local s=spec.lex.skip[i]
                if s.kind=="Whitespace" then out[#out+1]={kind="Whitespace"}
                elseif s.kind=="LineComment" then out[#out+1]={kind="LineComment",open=s.open}
                elseif s.kind=="BlockComment" then out[#out+1]={kind="BlockComment",open=s.open,close=s.close} end
            end; return out
        end)() or nil,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- VM — one while-loop, three stacks
-- ═══════════════════════════════════════════════════════════════

local function match_str_bytes(input, len, pos, str)
    if pos + #str > len then return false end
    for i=0,#str-1 do if input[pos+i] ~= str:byte(i+1) then return false end end
    return true
end

local function is_space(b) return b==32 or b==9 or b==10 or b==13 end

local function normalize_actions(a)
    if a == TREE_ACTIONS then return a end
    if not a then return EMPTY_ACTIONS end
    if a.__gps_normalized then return a end
    return { __gps_normalized=true, tokens=a.tokens or a.token or {}, rules=a.rules or a.rule or {} }
end

local function apply_tok_action(actions, name, source, st, sp)
    if actions == TREE_ACTIONS then return { kind=name, text=source:sub(st+1,sp), start=st, stop=sp } end
    local a = actions.tokens[name]
    if a ~= nil then return type(a)=="function" and a(source,st,sp,name) or a end
    return source:sub(st+1, sp)
end

local function apply_rule_action(actions, name, val, source, st, sp)
    if actions == TREE_ACTIONS then return { kind=name, value=val, start=st, stop=sp } end
    local a = actions.rules[name]
    if a ~= nil then return a(val, source, st, sp, name) end
    return val
end

local function vm_run(code, input_string, mode, aux)
    local source = input_string
    local actions = mode == MODE_REDUCE and normalize_actions(aux) or nil
    local do_reduce = (mode == MODE_REDUCE)
    local do_emit = (mode == MODE_EMIT)

    local cop, ca, cb, cname, caux = code.op, code.a, code.b, code.name, code.aux
    local code_n = code.n

    -- ── input backend ────────────────────────────────────────
    local pos, last_end, last_start
    local tok_kind, tok_start, tok_stop
    local compiled, lex_next, inp_buf, inp_len
    local skip_defs

    local function skip_ws()
        while pos < inp_len do
            local adv = false
            for i=1,#skip_defs do
                local sd = skip_defs[i]
                if sd.kind=="Whitespace" then
                    if is_space(inp_buf[pos]) then
                        pos=pos+1; while pos<inp_len and is_space(inp_buf[pos]) do pos=pos+1 end; adv=true; break end
                elseif sd.kind=="LineComment" then
                    if match_str_bytes(inp_buf,inp_len,pos,sd.open) then
                        pos=pos+#sd.open; while pos<inp_len and inp_buf[pos]~=10 do pos=pos+1 end
                        if pos<inp_len then pos=pos+1 end; adv=true; break end
                elseif sd.kind=="BlockComment" then
                    if match_str_bytes(inp_buf,inp_len,pos,sd.open) then
                        pos=pos+#sd.open
                        while pos<inp_len do
                            if match_str_bytes(inp_buf,inp_len,pos,sd.close) then pos=pos+#sd.close; break end
                            pos=pos+1 end; adv=true; break end
                end
            end
            if not adv then break end
        end
    end

    local is_token_mode = (code.parse_mode == "token")

    if is_token_mode then
        compiled = code.lexer.compile(input_string)
        lex_next = code.lexer.lex_next
        pos = 0; tok_kind = -1; tok_start = 0; tok_stop = 0; last_end = 0; last_start = 0
        local function advance()
            local np,k,st,sp = lex_next(compiled, pos)
            if np == nil then tok_kind=0; tok_start=pos; tok_stop=pos
            else pos=np; tok_kind=k; tok_start=st; tok_stop=sp end
        end
        advance() -- prime
        -- redefine advance as upvalue
        -- we need it available in the loop. put it in a local.
        -- Actually, inline it below.
        -- For now, store advance:
        skip_ws = advance -- reuse variable name
    else
        local len = #input_string
        inp_buf = ffi.new("uint8_t[?]", len)
        ffi.copy(inp_buf, input_string, len)
        inp_len = len
        pos = 0; last_end = 0; last_start = 0
        skip_defs = code.skip_defs or {}
    end

    -- save/restore for backtracking
    local function save_pos()
        if is_token_mode then return pos, tok_kind, tok_start, tok_stop, last_end, last_start
        else return pos, last_end, last_start end
    end
    local function restore_pos(...)
        if is_token_mode then
            pos, tok_kind, tok_start, tok_stop, last_end, last_start = ...
        else
            pos, last_end, last_start = ...
        end
    end

    local function peek_key()
        if is_token_mode then return tok_kind end
        skip_ws()
        if pos >= inp_len then return nil end
        return "#b" .. tostring(inp_buf[pos])
    end

    local function at_eof()
        if is_token_mode then return tok_kind == 0 end
        skip_ws(); return pos >= inp_len
    end

    local function make_error(msg)
        if is_token_mode then
            return false, { pos=tok_start, text=source:sub(tok_start+1, math.min(#source, tok_stop+16)), message=msg or "parse error" }
        else
            skip_ws()
            return false, { pos=pos, text=source:sub(pos+1, math.min(#source, pos+16)), message=msg or "parse error" }
        end
    end

    -- ── stacks ───────────────────────────────────────────────
    local cs, cs_top = {}, 0         -- call stack: return addresses
    local cs_start = {}              -- call stack: rule start positions (for reduce)
    local cs_name = {}               -- call stack: rule names

    local bt, bt_top = {}, 0         -- backtrack stack
    -- Each frame must restore all explicit runtime recursion state.
    -- Once grammar recursion is lowered into this VM, backtracking has to
    -- restore not just input position but also every stack depth that may
    -- have changed while exploring the failed arm.
    local bt_pos = {}     -- saved position state (packed)
    local bt_vn = {}      -- saved value stack depth
    local bt_mn = {}      -- saved mark stack depth
    local bt_cn = {}      -- saved call stack depth
    local bt_ln = {}      -- saved emit log depth
    local bt_addr = {}    -- fail address

    local vs, vs_top = {}, 0         -- value stack (reduce mode)
    local ms, ms_top = {}, 0         -- mark stack (reduce mode)

    -- emit log (emit mode)
    local ln, lk, lname_log, lst, lsp = 0, {}, {}, {}, {}

    -- fail handler: pop backtrack stack, restore state, jump to fail addr
    local function do_fail()
        if bt_top == 0 then return nil end
        restore_pos(unpack(bt_pos[bt_top]))
        vs_top = bt_vn[bt_top]
        ms_top = bt_mn[bt_top]
        cs_top = bt_cn[bt_top]
        ln = bt_ln[bt_top]
        local addr = bt_addr[bt_top]
        bt_top = bt_top - 1
        return addr
    end

    -- ── the ONE loop ─────────────────────────────────────────
    local ip = code.start_addr
    -- simulate initial CALL to start rule (so RET works)
    cs_top = 1; cs[1] = code_n + 1 -- return to past END
    cs_start[1] = is_token_mode and tok_start or pos
    cs_name[1] = code.start_name

    while ip <= code_n do
        local o = cop[ip]

        -- ── terminals (fail → backtrack stack) ───────────────
        if o == OP_MATCH_TOK then
            if tok_kind == ca[ip] then
                local st, sp = tok_start, tok_stop; last_start = st; last_end = sp
                local np,k,s2,p2 = lex_next(compiled, pos)
                if np==nil then tok_kind=0; tok_start=pos; tok_stop=pos
                else pos=np; tok_kind=k; tok_start=s2; tok_stop=p2 end
                if do_emit then ln=ln+1; lk[ln]=1; lname_log[ln]=cname[ip]; lst[ln]=st; lsp[ln]=sp end
                ip = ip + 1
            else ip = do_fail(); if not ip then return make_error() end end

        elseif o == OP_MATCH_LIT then
            skip_ws(); local text = cname[ip]
            if match_str_bytes(inp_buf, inp_len, pos, text) then
                local st = pos; pos = pos + #text; last_start = st; last_end = pos
                if do_emit then ln=ln+1; lk[ln]=1; lname_log[ln]=text; lst[ln]=st; lsp[ln]=pos end
                ip = ip + 1
            else ip = do_fail(); if not ip then return make_error() end end

        elseif o == OP_MATCH_NUM then
            skip_ws(); local sp = pos; local ok = true
            if pos<inp_len and inp_buf[pos]==C_MINUS then pos=pos+1 end
            if pos<inp_len and inp_buf[pos]==C_0 then pos=pos+1
            elseif pos<inp_len and inp_buf[pos]>C_0 and inp_buf[pos]<=C_9 then
                while pos<inp_len and inp_buf[pos]>=C_0 and inp_buf[pos]<=C_9 do pos=pos+1 end
            else ok=false end
            if ok and pos<inp_len and inp_buf[pos]==C_DOT then
                pos=pos+1
                if pos>=inp_len or inp_buf[pos]<C_0 or inp_buf[pos]>C_9 then ok=false
                else while pos<inp_len and inp_buf[pos]>=C_0 and inp_buf[pos]<=C_9 do pos=pos+1 end end
            end
            if ok and pos<inp_len and (inp_buf[pos]==C_e or inp_buf[pos]==C_E) then
                pos=pos+1; if pos<inp_len and (inp_buf[pos]==C_PLUS or inp_buf[pos]==C_MINUS) then pos=pos+1 end
                if pos>=inp_len or inp_buf[pos]<C_0 or inp_buf[pos]>C_9 then ok=false
                else while pos<inp_len and inp_buf[pos]>=C_0 and inp_buf[pos]<=C_9 do pos=pos+1 end end
            end
            if ok then
                last_start = sp; last_end = pos
                if do_emit then ln=ln+1; lk[ln]=1; lname_log[ln]="NUMBER"; lst[ln]=sp; lsp[ln]=pos end
                ip = ip + 1
            else pos=sp; ip = do_fail(); if not ip then return make_error() end end

        elseif o == OP_MATCH_STR then
            skip_ws()
            if pos<inp_len and inp_buf[pos]==C_QUOTE then
                local sp = pos; pos=pos+1; local str_ok = false
                while pos<inp_len do
                    local c = inp_buf[pos]
                    if c==C_QUOTE then last_end=pos+1; pos=pos+1; str_ok=true; break
                    elseif c==C_BSLASH then pos=pos+2
                    else pos=pos+1 end
                end
                if str_ok then
                    last_start = sp
                    if do_emit then ln=ln+1; lk[ln]=1; lname_log[ln]="STRING"; lst[ln]=sp; lsp[ln]=pos end
                    ip = ip + 1
                else pos=sp; ip = do_fail(); if not ip then return make_error() end end
            else ip = do_fail(); if not ip then return make_error() end end

        -- ── control flow ─────────────────────────────────────
        elseif o == OP_CALL then
            cs_top = cs_top + 1
            cs[cs_top] = ip + 1
            cs_start[cs_top] = is_token_mode and tok_start or pos
            cs_name[cs_top] = cname[ip]
            ip = ca[ip]

        elseif o == OP_RET then
            local ret = cs[cs_top]
            if do_emit then
                ln=ln+1; lk[ln]=2; lname_log[ln]=cs_name[cs_top]
                lst[ln]=cs_start[cs_top]; lsp[ln]=last_end
            end
            cs_top = cs_top - 1
            ip = ret

        elseif o == OP_CHOICE then
            bt_top = bt_top + 1
            bt_pos[bt_top] = { save_pos() }
            bt_vn[bt_top] = vs_top
            bt_mn[bt_top] = ms_top
            bt_cn[bt_top] = cs_top
            bt_ln[bt_top] = ln
            bt_addr[bt_top] = ca[ip]
            ip = ip + 1

        elseif o == OP_COMMIT then
            bt_top = bt_top - 1
            ip = ca[ip]

        elseif o == OP_PARTIAL_COMMIT then
            bt_pos[bt_top] = { save_pos() }
            bt_vn[bt_top] = vs_top
            bt_mn[bt_top] = ms_top
            bt_cn[bt_top] = cs_top
            bt_ln[bt_top] = ln
            ip = ca[ip]

        elseif o == OP_FAIL then
            ip = do_fail(); if not ip then return make_error() end

        elseif o == OP_JUMP then
            ip = ca[ip]

        elseif o == OP_DISPATCH then
            local key = peek_key()
            local dtable = caux[ip]
            ip = dtable[key] or ca[ip]

        -- ── value ops (reduce mode) ──────────────────────────
        elseif o == OP_APPLY_TOKEN then
            if do_reduce then
                vs_top = vs_top + 1
                vs[vs_top] = apply_tok_action(actions, cname[ip], source, last_start or 0, last_end)
            end
            ip = ip + 1

        elseif o == OP_APPLY_RULE then
            if do_reduce then
                local val = vs[vs_top]; vs_top = vs_top - 1
                local st = cs_start[cs_top + 1] or 0
                vs_top = vs_top + 1
                vs[vs_top] = apply_rule_action(actions, cname[ip], val, source, st, last_end)
            end
            ip = ip + 1

        elseif o == OP_PUSH_MARK then
            if do_reduce then ms_top = ms_top + 1; ms[ms_top] = vs_top end
            ip = ip + 1

        elseif o == OP_PACK_ALL then
            if do_reduce then
                local mark = ms[ms_top]; ms_top = ms_top - 1
                local arr = {}
                for j = mark + 1, vs_top do if vs[j] ~= nil then arr[#arr+1] = vs[j] end end
                vs_top = mark + 1; vs[vs_top] = arr
            end
            ip = ip + 1

        elseif o == OP_PACK_INDEX then
            if do_reduce then
                local mark = ms[ms_top]; ms_top = ms_top - 1
                vs_top = mark + 1; vs[vs_top] = vs[mark + ca[ip]]
            end
            ip = ip + 1

        elseif o == OP_PACK_PAIR then
            if do_reduce then
                local mark = ms[ms_top]; ms_top = ms_top - 1
                vs_top = mark + 1; vs[vs_top] = { vs[mark + ca[ip]], vs[mark + cb[ip]] }
            end
            ip = ip + 1

        elseif o == OP_PUSH_NIL then
            if do_reduce then vs_top = vs_top + 1; vs[vs_top] = nil end
            ip = ip + 1

        elseif o == OP_END then
            break

        else
            error("grammar3: unknown opcode "..tostring(o).." at ip="..ip, 2)
        end
    end

    -- ── finalize ─────────────────────────────────────────────
    if not at_eof() then return make_error("trailing input") end

    if mode == MODE_MATCH then
        return true, true
    elseif mode == MODE_EMIT then
        -- add top-level rule log entry
        ln=ln+1; lk[ln]=2; lname_log[ln]=code.start_name
        lst[ln]=0; lsp[ln]=last_end
        if aux then
            local on_tok = aux.token or aux.on_token
            local on_rule = aux.rule or aux.on_rule
            for i=1,ln do
                if lk[i]==1 then if on_tok then on_tok(aux, lname_log[i], source, lst[i], lsp[i]) end
                else if on_rule then on_rule(aux, lname_log[i], source, lst[i], lsp[i]) end end
            end
        end
        return true, ln
    elseif mode == MODE_REDUCE then
        local val = vs_top > 0 and vs[vs_top] or nil
        val = apply_rule_action(actions, code.start_name, val, source, 0, last_end)
        return true, val
    end
end

-- need unpack
local unpack = table.unpack or unpack

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════

local PARSER_MT = {}
local REDUCER_MT = {}

local function fmt_err(v)
    return string.format("grammar3 parse error at %d near %q (%s)",
        v.pos or -1, v.text or "", v.message or "error")
end

function PARSER_MT:try_match(s) return vm_run(self._code, s, MODE_MATCH) end
function PARSER_MT:match(s) return (self:try_match(s)) end
function PARSER_MT:try_emit(s, sink) return vm_run(self._code, s, MODE_EMIT, sink) end
function PARSER_MT:emit(s, sink) local ok,v=self:try_emit(s,sink); if not ok then error(fmt_err(v),2) end; return v end
function PARSER_MT:try_reduce(s, a) return vm_run(self._code, s, MODE_REDUCE, a) end
function PARSER_MT:reduce(s, a) local ok,v=self:try_reduce(s,a); if not ok then error(fmt_err(v),2) end; return v end
function PARSER_MT:try_tree(s) return vm_run(self._code, s, MODE_REDUCE, TREE_ACTIONS) end
function PARSER_MT:tree(s) local ok,v=self:try_tree(s); if not ok then error(fmt_err(v),2) end; return v end
PARSER_MT.parse = PARSER_MT.tree
PARSER_MT.try_parse = PARSER_MT.try_tree

function PARSER_MT:reducer(actions)
    local cache = rawget(self, "_rc"); local key = actions or TREE_ACTIONS
    local hit = cache and cache[key]; if hit then return hit end
    cache = cache or setmetatable({}, {__mode="k"}); rawset(self, "_rc", cache)
    local fam = setmetatable({
        __gps_reducer=true, parser=self, actions=normalize_actions(actions), start=self.start,
    }, {__index=REDUCER_MT})
    cache[key]=fam; return fam
end

function REDUCER_MT:try_parse(s) return vm_run(self.parser._code, s, MODE_REDUCE, self.actions) end
function REDUCER_MT:parse(s) local ok,v=self:try_parse(s); if not ok then error(fmt_err(v),2) end; return v end

-- ═══════════════════════════════════════════════════════════════
-- MODULE ENTRY
-- ═══════════════════════════════════════════════════════════════

return function(GPS_ref, asdl_context)
    M_framework = GPS_ref

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
        if type(spec) ~= "table" or not spec.lex or not spec.parse then
            error("grammar3: expected Grammar.Spec", 2)
        end
        local src_rules = get_rule_map(spec)
        if not src_rules[spec.parse.start] then
            error("grammar3: unknown start '"..spec.parse.start.."'", 2)
        end
        local pm = detect_parse_mode(src_rules, spec.parse.start)
        local rules = lower_rule_map(src_rules)
        local _, rule_order = collect_reachable(rules, spec.parse.start)
        local token_ids = nil
        local lexer = nil
        if pm == "token" then
            lexer = build_lexer(GPS_ref, spec, collect_used_tokens(rules, spec.parse.start))
            token_ids = lexer.TOKEN
        end
        local info = compute_nullable_first(rules, rule_order, token_ids, pm)
        reject_left_recursion(rule_order, rules, info)
        local code = compile_opcodes(rules, spec.parse.start, pm, lexer, spec, info)

        return setmetatable({
            __gps_parser=true, _code=code, start=spec.parse.start, Grammar=CTX.Grammar,
        }, {__index=PARSER_MT})
    end

    local Api = {}
    function Api.context() return CTX end
    function Api.schema() return SCHEMA end
    function Api.compile(spec) return compile(spec) end
    function Api.new()
        return setmetatable({Grammar=CTX.Grammar}, {
            __index=function(_, k) return Api[k] or CTX.Grammar[k] end,
        })
    end

    return setmetatable(Api, {
        __call=function(_, spec)
            if spec==nil then return Api.new() end
            return compile(spec)
        end,
    })
end
