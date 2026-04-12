-- lsp/parser.lua
--
-- Recursive descent Lua 5.1/JIT parser as pvm.lower("parse").
--
-- Input:  SourceFile ASDL node
-- Output: (File ASDL node, ServerMeta with anchor→position mappings)
--
-- The parser drains lex_with_positions(source_file) to get Token nodes + positions,
-- then does standard recursive descent producing AST nodes.
-- All AST nodes are ASDL unique (no Range) → structural interning.
--
-- Anchors: the parser records (asdl_node → position) mappings via the mark()
-- function. These become ServerAnchorPoint entries in ServerMeta, used by the
-- LSP adapter to map from AST identity → source range.
--
-- Because AST nodes carry NO position:
--   local x = 42  at line 1  and  local x = 42  at line 50
--   produce the SAME interned Item.
--   → bind_symbols sees ONE cache entry for both → maximum reuse.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")
local Lexer = require("lsp.lexer")

local M = {}

function M.new(ctx)
    ctx = ctx or ASDL.context()
    local C = ctx.Lua
    local lexer_engine = Lexer.new(ctx)

    -- ══════════════════════════════════════════════════════════
    --  Parser core
    -- ══════════════════════════════════════════════════════════

    local function make_parser(tokens, positions, uri)
        local pos = 1
        local count = #tokens
        local anchors = {}     -- {anchor_ref, lsp_range, label}
        local anchor_n = 0

        -- ── Token access ───────────────────────────────────
        local function peek()  return tokens[pos] end
        local function peek_kind()
            local t = tokens[pos]
            return t and t.kind or "<eof>"
        end
        local function peek_value()
            local t = tokens[pos]
            return t and t.value or ""
        end
        local function advance()
            local t = tokens[pos]
            pos = pos + 1
            return t
        end
        local function expect(kind)
            local t = tokens[pos]
            if not t or t.kind ~= kind then
                error(string.format("parse error at token %d: expected '%s', got '%s'",
                    pos, kind, t and t.kind or "<eof>"), 0)
            end
            pos = pos + 1
            return t
        end
        local function check(kind)
            local t = tokens[pos]
            return t and t.kind == kind
        end
        local function match(kind)
            if check(kind) then pos = pos + 1; return true end
            return false
        end

        -- ── Anchor recording ───────────────────────────────
        -- Records mapping: tostring(node) → source range.
        -- The node's tostring is its interned identity key.
        local function mark(node, start_tok, end_tok)
            if not node then return node end
            local sp = positions[start_tok] or positions[pos - 1] or { line = 1, col = 1 }
            local ep = positions[end_tok or (pos - 1)] or sp
            anchor_n = anchor_n + 1
            anchors[anchor_n] = {
                anchor = C.AnchorRef(tostring(node)),
                range = C.LspRange(
                    C.LspPos(sp.line - 1, sp.col - 1),  -- 0-based for LSP
                    C.LspPos(ep.line - 1, (ep.end_offset or ep.offset) - (positions[ep.line == sp.line and start_tok or (end_tok or pos - 1)] or ep).offset + ep.col)
                ),
            }
            return node
        end

        -- Simpler mark using token index range
        local function mark_range(node, start_pos, end_pos)
            if not node then return node end
            local sp = positions[start_pos] or { line = 1, col = 1, offset = 1, end_offset = 1 }
            local ep = positions[end_pos or (pos - 1)] or sp
            anchor_n = anchor_n + 1
            anchors[anchor_n] = {
                anchor = C.AnchorRef(tostring(node)),
                range = C.LspRange(
                    C.LspPos(sp.line - 1, sp.col - 1),
                    C.LspPos(ep.line - 1, ep.col - 1 + (ep.end_offset - ep.offset + 1))
                ),
            }
            return node
        end

        -- ── Forward declarations ───────────────────────────
        local parse_expr, parse_block, parse_stmt

        -- ── Expression parsing ─────────────────────────────

        local function parse_name()
            local p0 = pos
            local t = expect("<name>")
            return mark_range(C.Name(t.value), p0)
        end

        local function parse_namelist()
            local names = { parse_name() }
            while match(",") do
                names[#names + 1] = parse_name()
            end
            return names
        end

        local function parse_funcbody()
            local p0 = pos
            expect("(")
            local params = {}
            local vararg = false
            if not check(")") then
                if check("...") then
                    advance(); vararg = true
                else
                    local pn = C.PName(expect("<name>").value)
                    mark_range(pn, pos - 1)
                    params[1] = pn
                    while match(",") do
                        if check("...") then
                            advance(); vararg = true; break
                        end
                        local ppn = C.PName(expect("<name>").value)
                        mark_range(ppn, pos - 1)
                        params[#params + 1] = ppn
                    end
                end
            end
            expect(")")
            local body = parse_block()
            expect("end")
            return mark_range(C.FuncBody(params, vararg, body), p0)
        end

        local function parse_fieldlist()
            local fields = {}
            while true do
                local p0 = pos
                if check("[") then
                    advance()
                    local key = parse_expr()
                    expect("]")
                    expect("=")
                    local val = parse_expr()
                    fields[#fields + 1] = mark_range(C.PairField(key, val), p0)
                elseif check("<name>") and positions[pos + 1] and tokens[pos + 1] and tokens[pos + 1].kind == "=" then
                    local name = advance().value
                    advance() -- =
                    local val = parse_expr()
                    fields[#fields + 1] = mark_range(C.NameField(name, val), p0)
                elseif check("}") then
                    break
                else
                    local val = parse_expr()
                    fields[#fields + 1] = mark_range(C.ArrayField(val), p0)
                end
                if not match(",") then
                    match(";")  -- both , and ; are field separators
                    -- if next is }, we're done
                    if check("}") then break end
                    -- if no separator and not }, might be end of fields
                    -- Lua allows trailing separator, and we should also handle missing separator gracefully
                end
            end
            return fields
        end

        local function parse_primary_expr()
            local p0 = pos
            local k = peek_kind()

            if k == "<name>" then
                local name = advance().value
                return mark_range(C.NameRef(name), p0)

            elseif k == "(" then
                advance()
                local inner = parse_expr()
                expect(")")
                return mark_range(C.Paren(inner), p0)

            else
                error(string.format("parse error at token %d: unexpected '%s' in expression",
                    pos, k), 0)
            end
        end

        local function parse_args()
            local k = peek_kind()
            if k == "(" then
                advance()
                local args = {}
                if not check(")") then
                    args[1] = parse_expr()
                    while match(",") do
                        args[#args + 1] = parse_expr()
                    end
                end
                expect(")")
                return args
            elseif k == "{" then
                local p0 = pos
                advance()
                local fields = parse_fieldlist()
                expect("}")
                return { mark_range(C.TableCtor(fields), p0) }
            elseif k == "<string>" then
                local t = advance()
                return { mark_range(C.String(t.value), pos - 1) }
            else
                error(string.format("parse error at token %d: expected function arguments, got '%s'", pos, k), 0)
            end
        end

        local function parse_suffixed_expr()
            local p0 = pos
            local base = parse_primary_expr()

            while true do
                local k = peek_kind()
                if k == "." then
                    advance()
                    local key = expect("<name>").value
                    base = mark_range(C.Field(base, key), p0)
                elseif k == "[" then
                    advance()
                    local key = parse_expr()
                    expect("]")
                    base = mark_range(C.Index(base, key), p0)
                elseif k == ":" then
                    advance()
                    local method = expect("<name>").value
                    local args = parse_args()
                    base = mark_range(C.MethodCall(base, method, args), p0)
                elseif k == "(" or k == "{" or k == "<string>" then
                    local args = parse_args()
                    base = mark_range(C.Call(base, args), p0)
                else
                    break
                end
            end

            return base
        end

        local function parse_simple_expr()
            local p0 = pos
            local k = peek_kind()

            if k == "<number>" then
                return mark_range(C.Number(advance().value), p0)
            elseif k == "<string>" then
                return mark_range(C.String(advance().value), p0)
            elseif k == "nil" then
                advance(); return C.Nil()
            elseif k == "true" then
                advance(); return mark_range(C.True(), p0)
            elseif k == "false" then
                advance(); return mark_range(C.False(), p0)
            elseif k == "..." then
                advance(); return mark_range(C.Vararg(), p0)
            elseif k == "function" then
                advance()
                return mark_range(C.FunctionExpr(parse_funcbody()), p0)
            elseif k == "{" then
                advance()
                local fields = parse_fieldlist()
                expect("}")
                return mark_range(C.TableCtor(fields), p0)
            else
                return parse_suffixed_expr()
            end
        end

        -- Operator precedence
        local UNARY_OPS = { ["-"] = true, ["not"] = true, ["#"] = true, ["~"] = true }

        local BINARY_PREC = {
            ["or"]  = {1, 1},
            ["and"] = {2, 2},
            ["<"]   = {3, 3}, [">"]  = {3, 3}, ["<="] = {3, 3}, [">="] = {3, 3},
            ["~="]  = {3, 3}, ["=="] = {3, 3},
            ["|"]   = {4, 4},
            ["~"]   = {5, 5},
            ["&"]   = {6, 6},
            ["<<"]  = {7, 7}, [">>"] = {7, 7},
            [".."]  = {8, 7},  -- right-associative
            ["+"]   = {9, 9}, ["-"]  = {9, 9},
            ["*"]   = {10, 10}, ["/"] = {10, 10}, ["//"] = {10, 10}, ["%"] = {10, 10},
            ["^"]   = {12, 11},  -- right-associative
        }

        local function parse_unary()
            local p0 = pos
            local k = peek_kind()
            if UNARY_OPS[k] then
                advance()
                local val = parse_unary()
                return mark_range(C.Unary(k, val), p0)
            end
            return parse_simple_expr()
        end

        local function parse_binary(min_prec)
            local p0 = pos
            local lhs = parse_unary()

            while true do
                local k = peek_kind()
                local prec = BINARY_PREC[k]
                if not prec or prec[1] < min_prec then break end
                advance()
                local rhs = parse_binary(prec[2] + 1)
                lhs = mark_range(C.Binary(k, lhs, rhs), p0)
            end

            return lhs
        end

        parse_expr = function()
            return parse_binary(1)
        end

        local function parse_exprlist()
            local exprs = { parse_expr() }
            while match(",") do
                exprs[#exprs + 1] = parse_expr()
            end
            return exprs
        end

        -- ── LValue parsing ─────────────────────────────────

        local function expr_to_lvalue(expr)
            if expr.kind == "NameRef" then
                return C.LName(expr.name)
            elseif expr.kind == "Field" then
                return C.LField(expr.base, expr.key)
            elseif expr.kind == "Index" then
                return C.LIndex(expr.base, expr.key)
            else
                -- fallback: treat as name
                return C.LName("_")
            end
        end

        -- ── Statement parsing ──────────────────────────────

        local function parse_if_stmt()
            local p0 = pos
            advance() -- if
            local cond = parse_expr()
            expect("then")
            local body = parse_block()
            local arms = { C.CondBlock(cond, body) }

            while match("elseif") do
                local econd = parse_expr()
                expect("then")
                local ebody = parse_block()
                arms[#arms + 1] = C.CondBlock(econd, ebody)
            end

            local else_block = C.Block({})
            if match("else") then
                else_block = parse_block()
            end
            expect("end")
            return mark_range(C.If(arms, else_block), p0)
        end

        local function parse_while_stmt()
            local p0 = pos
            advance() -- while
            local cond = parse_expr()
            expect("do")
            local body = parse_block()
            expect("end")
            return mark_range(C.While(cond, body), p0)
        end

        local function parse_repeat_stmt()
            local p0 = pos
            advance() -- repeat
            local body = parse_block()
            expect("until")
            local cond = parse_expr()
            return mark_range(C.Repeat(body, cond), p0)
        end

        local function parse_for_stmt()
            local p0 = pos
            advance() -- for
            local name = expect("<name>").value

            if match("=") then
                -- numeric for
                local init = parse_expr()
                expect(",")
                local limit = parse_expr()
                local step = check(",") and (advance() and parse_expr()) or C.Number("1")
                expect("do")
                local body = parse_block()
                expect("end")
                return mark_range(C.ForNum(name, init, limit, step, body), p0)
            else
                -- generic for
                local names = { mark_range(C.Name(name), p0 + 1) }
                while match(",") do
                    names[#names + 1] = parse_name()
                end
                expect("in")
                local iter = parse_exprlist()
                expect("do")
                local body = parse_block()
                expect("end")
                return mark_range(C.ForIn(names, iter, body), p0)
            end
        end

        local function parse_local_stmt()
            local p0 = pos
            advance() -- local

            if match("function") then
                local fname = expect("<name>").value
                local body = parse_funcbody()
                return mark_range(C.LocalFunction(fname, body), p0)
            end

            local names = { parse_name() }
            while match(",") do
                names[#names + 1] = parse_name()
            end

            local values = {}
            if match("=") then
                values = parse_exprlist()
            end
            return mark_range(C.LocalAssign(names, values), p0)
        end

        local function parse_function_stmt()
            local p0 = pos
            advance() -- function

            -- Parse function name: a.b.c or a.b.c:d
            local fname_p0 = pos
            local name_str = expect("<name>").value
            local lv = mark_range(C.LName(name_str), fname_p0)

            while match(".") do
                local key = expect("<name>").value
                -- Convert to LField: the base is the expr equivalent
                local base_expr = (lv.kind == "LName") and C.NameRef(lv.name) or
                    (lv.kind == "LField") and C.Field(lvalue_to_expr(lv), lv.key) or
                    C.NameRef(name_str)
                lv = C.LField(base_expr, key)
            end
            if match(":") then
                local method = expect("<name>").value
                local base_expr = (lv.kind == "LName") and C.NameRef(lv.name) or
                    (lv.kind == "LField") and C.Field(lvalue_to_expr(lv), lv.key) or
                    C.NameRef(name_str)
                lv = C.LMethod(base_expr, method)
            end

            local body = parse_funcbody()
            return mark_range(C.Function(lv, body), p0)
        end

        local function parse_return_stmt()
            local p0 = pos
            advance() -- return
            local values = {}
            local k = peek_kind()
            if k ~= "end" and k ~= "else" and k ~= "elseif" and k ~= "until" and k ~= "<eof>" and k ~= ";" then
                values = parse_exprlist()
            end
            match(";") -- optional semicolon after return
            return mark_range(C.Return(values), p0)
        end

        -- Convert LValue to Expr (for chained field access in function names)
        local function lvalue_to_expr(lv)
            if lv.kind == "LName" then return C.NameRef(lv.name)
            elseif lv.kind == "LField" then return C.Field(lv.base, lv.key)
            elseif lv.kind == "LIndex" then return C.Index(lv.base, lv.key)
            else return C.NameRef("_") end
        end

        parse_stmt = function()
            local p0 = pos
            local k = peek_kind()

            if k == "if"       then return parse_if_stmt()
            elseif k == "while"  then return parse_while_stmt()
            elseif k == "repeat" then return parse_repeat_stmt()
            elseif k == "for"    then return parse_for_stmt()
            elseif k == "do"     then
                advance()
                local body = parse_block()
                expect("end")
                return mark_range(C.Do(body), p0)
            elseif k == "local"  then return parse_local_stmt()
            elseif k == "function" then return parse_function_stmt()
            elseif k == "return" then return parse_return_stmt()
            elseif k == "break"  then
                advance()
                return mark_range(C.Break(), p0)
            elseif k == "goto"   then
                advance()
                local label = expect("<name>").value
                return mark_range(C.Goto(label), p0)
            elseif k == "::"     then
                advance()
                local label = expect("<name>").value
                expect("::")
                return mark_range(C.Label(label), p0)
            elseif k == ";"      then
                advance()
                return nil  -- empty statement
            else
                -- Expression statement: assignment or function call
                local expr = parse_suffixed_expr()

                -- Check for assignment
                if check("=") or check(",") then
                    local lhs = { expr_to_lvalue(expr) }
                    while match(",") do
                        lhs[#lhs + 1] = expr_to_lvalue(parse_suffixed_expr())
                    end
                    expect("=")
                    local rhs = parse_exprlist()
                    return mark_range(C.Assign(lhs, rhs), p0)
                end

                -- Must be a function call
                if expr.kind == "Call" or expr.kind == "MethodCall" then
                    return mark_range(C.CallStmt(expr.callee or expr.recv, expr.args or {}), p0)
                end

                -- Fallback: treat as call statement
                return mark_range(C.CallStmt(expr, {}), p0)
            end
        end

        -- ── Doc comment parsing ────────────────────────────

        local function parse_doc_comment(text)
            local tags = {}

            local primitive = {
                number = C.TNumber(), string = C.TString(), boolean = C.TBoolean(),
                ["nil"] = C.TNil(), any = C.TAny(),
            }

            local function trim(s)
                return (s or ""):match("^%s*(.-)%s*$")
            end

            local function parse_doc_type(s)
                s = trim(s)
                if s == "" then return C.TAny() end

                local parts = {}
                for raw in s:gmatch("[^|]+") do
                    local p = trim(raw)
                    local optional = false
                    if p:sub(-1) == "?" then
                        optional = true
                        p = p:sub(1, -2)
                    end

                    local arr = 0
                    while p:sub(-2) == "[]" do
                        arr = arr + 1
                        p = p:sub(1, -3)
                    end

                    local t = primitive[p] or C.TNamed(p)
                    for _ = 1, arr do t = C.TArray(t) end
                    if optional then t = C.TOptional(t) end
                    parts[#parts + 1] = t
                end

                if #parts == 0 then return C.TAny() end
                if #parts == 1 then return parts[1] end
                return C.TUnion(parts)
            end

            -- ---@class Name[: Base, Base2]
            local cls, extends = text:match("%-%-%-@class%s+([%w_%.]+)%s*:%s*(.+)")
            if cls then
                local ex = {}
                for e in tostring(extends or ""):gmatch("[^,]+") do
                    ex[#ex + 1] = parse_doc_type(e)
                end
                tags[#tags + 1] = C.ClassTag(cls, ex)
                return tags
            end
            cls = text:match("%-%-%-@class%s+([%w_%.]+)")
            if cls then
                tags[#tags + 1] = C.ClassTag(cls, {})
                return tags
            end

            -- ---@field name[?] type
            local fname, fopt_name, ftype = text:match("%-%-%-@field%s+([%w_]+)(%??)%s+([%w_%.%[%]%|%?]+)")
            if fname then
                local typ = parse_doc_type(ftype)
                local optional = (fopt_name == "?")
                tags[#tags + 1] = C.FieldTag(fname, typ, optional)
                return tags
            end

            -- ---@param name type
            local pname, ptype = text:match("%-%-%-@param%s+([%w_]+)%s+([%w_%.%[%]%|%?]+)")
            if pname then
                tags[#tags + 1] = C.ParamTag(pname, parse_doc_type(ptype))
                return tags
            end

            -- ---@return type
            local rtype = text:match("%-%-%-@return%s+([%w_%.%[%]%|%?]+)")
            if rtype then
                tags[#tags + 1] = C.ReturnTag({ parse_doc_type(rtype) })
                return tags
            end

            -- ---@alias name type
            local aname, atype = text:match("%-%-%-@alias%s+([%w_%.]+)%s+([%w_%.%[%]%|%?]+)")
            if aname then
                tags[#tags + 1] = C.AliasTag(aname, parse_doc_type(atype))
                return tags
            end

            -- ---@type type
            local ttype = text:match("%-%-%-@type%s+([%w_%.%[%]%|%?]+)")
            if ttype then
                tags[#tags + 1] = C.TypeTag(parse_doc_type(ttype))
                return tags
            end

            -- ---@generic Name
            local gname = text:match("%-%-%-@generic%s+([%w_]+)")
            if gname then
                tags[#tags + 1] = C.GenericTag(gname, {})
                return tags
            end

            -- ---@cast expr type
            local ctype = text:match("%-%-%-@cast%s+%w+%s+([%w_%.%[%]%|%?]+)")
            if ctype then
                tags[#tags + 1] = C.CastTag(parse_doc_type(ctype))
                return tags
            end

            -- ---@meta name text
            local mname, mtext = text:match("%-%-%-@(%w+)%s+(.*)")
            if mname then
                tags[#tags + 1] = C.MetaTag(mname, mtext)
                return tags
            end

            return tags
        end

        -- ── Scope extraction ───────────────────────────────
        -- Walks a Stmt tree and extracts flat NameOcc array.
        -- This replaces the expensive scope_events phase walk.
        -- Done once at parse time — O(n) over AST nodes, no pvm overhead.

        local function extract_scope(stmt)
            local out = {}
            local n = 0
            local function emit(occ) n = n + 1; out[n] = occ end

            local function walk_expr(e)
                if not e then return end
                local k = e.kind
                if k == "NameRef" then emit(C.OccRef(e.name))
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
                        elseif f.kind == "NameField" then walk_expr(f.value)
                        end
                    end
                elseif k == "Unary" then walk_expr(e.value)
                elseif k == "Binary" then walk_expr(e.lhs); walk_expr(e.rhs)
                elseif k == "Paren" then walk_expr(e.inner)
                end
                -- Nil, True, False, Number, String, Vararg → nothing
            end

            local function walk_lvalue(lv)
                if lv.kind == "LName" then emit(C.OccWrite(lv.name))
                elseif lv.kind == "LField" then walk_expr(lv.base)
                elseif lv.kind == "LIndex" then walk_expr(lv.base); walk_expr(lv.key)
                elseif lv.kind == "LMethod" then walk_expr(lv.base)
                end
            end

            local function walk_block(block)
                for i = 1, #block.items do walk_stmt(block.items[i].stmt) end
            end

            function walk_body(body, implicit_self)
                emit(C.OccScopeEnter(C.ScopeFunction))
                if implicit_self then
                    emit(C.OccDecl(C.DeclParam, "self"))
                end
                for i = 1, #body.params do
                    emit(C.OccDecl(C.DeclParam, body.params[i].name))
                end
                walk_block(body.body)
                emit(C.OccScopeExit(C.ScopeFunction))
            end

            function walk_stmt(s)
                if not s then return end
                local k = s.kind
                if k == "LocalAssign" then
                    for i = 1, #s.values do walk_expr(s.values[i]) end
                    for i = 1, #s.names do emit(C.OccDecl(C.DeclLocal, s.names[i].value)) end
                elseif k == "Assign" then
                    for i = 1, #s.rhs do walk_expr(s.rhs[i]) end
                    for i = 1, #s.lhs do walk_lvalue(s.lhs[i]) end
                elseif k == "LocalFunction" then
                    emit(C.OccDecl(C.DeclLocal, s.name))
                    walk_body(s.body)
                elseif k == "Function" then
                    local implicit_self = false
                    if s.name.kind == "LName" then
                        emit(C.OccWrite(s.name.name))
                    elseif s.name.kind == "LField" then walk_expr(s.name.base)
                    elseif s.name.kind == "LIndex" then walk_expr(s.name.base); walk_expr(s.name.key)
                    elseif s.name.kind == "LMethod" then
                        walk_expr(s.name.base)
                        implicit_self = true
                    end
                    walk_body(s.body, implicit_self)
                elseif k == "Return" then
                    for i = 1, #s.values do walk_expr(s.values[i]) end
                elseif k == "CallStmt" then
                    walk_expr(s.callee)
                    for i = 1, #s.args do walk_expr(s.args[i]) end
                elseif k == "If" then
                    for i = 1, #s.arms do
                        walk_expr(s.arms[i].cond)
                        emit(C.OccScopeEnter(C.ScopeIf))
                        walk_block(s.arms[i].body)
                        emit(C.OccScopeExit(C.ScopeIf))
                    end
                    if s.else_block then
                        emit(C.OccScopeEnter(C.ScopeElse))
                        walk_block(s.else_block)
                        emit(C.OccScopeExit(C.ScopeElse))
                    end
                elseif k == "While" then
                    walk_expr(s.cond)
                    emit(C.OccScopeEnter(C.ScopeWhile))
                    walk_block(s.body)
                    emit(C.OccScopeExit(C.ScopeWhile))
                elseif k == "Repeat" then
                    emit(C.OccScopeEnter(C.ScopeRepeat))
                    walk_block(s.body)
                    walk_expr(s.cond)
                    emit(C.OccScopeExit(C.ScopeRepeat))
                elseif k == "ForNum" then
                    walk_expr(s.init); walk_expr(s.limit); walk_expr(s.step)
                    emit(C.OccScopeEnter(C.ScopeFor))
                    emit(C.OccDecl(C.DeclLocal, s.name))
                    walk_block(s.body)
                    emit(C.OccScopeExit(C.ScopeFor))
                elseif k == "ForIn" then
                    for i = 1, #s.iter do walk_expr(s.iter[i]) end
                    emit(C.OccScopeEnter(C.ScopeFor))
                    for i = 1, #s.names do emit(C.OccDecl(C.DeclLocal, s.names[i].value)) end
                    walk_block(s.body)
                    emit(C.OccScopeExit(C.ScopeFor))
                elseif k == "Do" then
                    emit(C.OccScopeEnter(C.ScopeDo))
                    walk_block(s.body)
                    emit(C.OccScopeExit(C.ScopeDo))
                end
                -- Break, Goto, Label → nothing scope-relevant
            end

            walk_stmt(stmt)
            return out
        end

        -- ── Block parsing ──────────────────────────────────

        parse_block = function()
            local p0 = pos
            local items = {}
            local pending_tags = {}

            while true do
                local k = peek_kind()
                -- Block terminators
                if k == "end" or k == "else" or k == "elseif" or k == "until" or k == "<eof>" then
                    break
                end

                -- Doc comments
                if k == "<comment>" then
                    local t = advance()
                    if t.value:match("^%-%-%-@") then
                        local tags = parse_doc_comment(t.value)
                        for j = 1, #tags do
                            local tag = tags[j]
                            mark_range(tag, pos - 1)
                            pending_tags[#pending_tags + 1] = tag
                        end
                    end
                else
                    local ok, stmt = pcall(parse_stmt)
                    if ok and stmt then
                        local docs = {}
                        if #pending_tags > 0 then
                            docs[1] = C.DocBlock(pending_tags)
                            pending_tags = {}
                        end
                        items[#items + 1] = C.Item(docs, stmt)
                    elseif not ok then
                        -- Error recovery: skip token
                        advance()
                    end
                end
            end

            return C.Block(items)
        end

        -- ── Top-level parse ────────────────────────────────

        local function parse_file()
            local block = parse_block()
            local items = block.items
            if #items == 0 then
                items = { C.Item({}, C.Break()) }
            end
            local file = C.File(uri, items)

            -- Build ServerMeta from anchors
            local meta_positions = {}
            for i = 1, anchor_n do
                local a = anchors[i]
                meta_positions[i] = C.ServerAnchorPoint(a.anchor, a.range, "")
            end
            local meta = C.ServerMeta(meta_positions, "")

            return file, meta
        end

        return { parse_file = parse_file }
    end

    -- ══════════════════════════════════════════════════════════
    --  pvm.lower("parse") boundary
    -- ══════════════════════════════════════════════════════════
    --
    -- Drains lex_with_positions(source_file) → tokens + positions.
    -- Runs recursive descent.
    -- Returns (File, ServerMeta).
    --
    -- Cached per SourceFile identity. When source changes →
    -- new SourceFile → cache miss → re-parse. But the resulting
    -- AST Items that are structurally identical to before are the
    -- SAME interned objects → all downstream phases get cache hits.

    local parse = pvm.lower("parse", function(source_file)
        local lex_result = lexer_engine.lex_with_positions(source_file)
        local tokens = lex_result.tokens
        local positions = lex_result.positions

        local ok, parser = pcall(make_parser, tokens, positions, source_file.uri)
        if not ok then
            -- Hard fallback: return minimal File
            local file = C.File(source_file.uri, { C.Item({}, C.Break()) })
            local meta = C.ServerMeta({}, tostring(parser))
            return { file = file, meta = meta }
        end

        local ok2, file, meta = pcall(function() return parser.parse_file() end)
        if not ok2 then
            local err_file = C.File(source_file.uri, { C.Item({}, C.Break()) })
            local err_meta = C.ServerMeta({}, tostring(file))
            return { file = err_file, meta = err_meta }
        end

        return { file = file, meta = meta }
    end)

    return {
        C = C,
        context = ctx,
        lexer = lexer_engine,
        parse = parse,
    }
end

return M
