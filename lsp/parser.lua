-- lsp/parser.lua
--
-- Recursive descent Lua parser as pvm.phase("parse").
--
--   OpenDoc:parse() -> ParsedDoc
--
-- The parser drains lex_with_positions(open_doc) to obtain LexTok facts,
-- runs recursive descent, and yields one ParsedDoc.

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")
local ASDL = require("lsp.asdl")
local Lexer = require("lsp.lexer")

local M = {}

function M.new(ctx)
    ctx = ctx or ASDL.context()
    local C = ctx.Lua
    local lexer_engine = Lexer.new(ctx)

    local function offset_to_line_col(text, offset)
        local target = offset or 1
        if target < 1 then target = 1 end
        if target > #text + 1 then target = #text + 1 end
        local line, col = 1, 1
        for i = 1, target - 1 do
            local ch = text:sub(i, i)
            if ch == "\n" then
                line = line + 1
                col = 1
            else
                col = col + 1
            end
        end
        return line, col
    end

    local function make_parser(tokens, positions, uri)
        local pos = 1
        local anchors = {}
        local anchor_n = 0
        local top_items = {}
        local block_depth = 0

        local function raw_peek_kind()
            local t = tokens[pos]
            return t and t.kind or "<eof>"
        end
        local function raw_advance()
            local t = tokens[pos]
            pos = pos + 1
            return t
        end

        local function skip_comments()
            while true do
                local t = tokens[pos]
                if not t or t.kind ~= "<comment>" then break end
                if type(t.value) == "string" and t.value:match("^%-%-%-@") then break end
                pos = pos + 1
            end
        end

        local function peek_kind()
            skip_comments()
            local t = tokens[pos]
            return t and t.kind or "<eof>"
        end
        local function advance()
            skip_comments()
            local t = tokens[pos]
            pos = pos + 1
            return t
        end
        local function expect(kind)
            skip_comments()
            local t = tokens[pos]
            if not t or t.kind ~= kind then
                error(string.format("parse error at token %d: expected '%s', got '%s'", pos, kind, t and t.kind or "<eof>"), 0)
            end
            pos = pos + 1
            return t
        end
        local function check(kind)
            skip_comments()
            local t = tokens[pos]
            return t and t.kind == kind
        end
        local function match(kind)
            if check(kind) then pos = pos + 1; return true end
            return false
        end

        local function mark_range(node, start_pos, end_pos)
            if not node then return node end
            local sp = positions[start_pos] or { line = 1, col = 1, start_offset = 1, end_offset = 1 }
            local ep = positions[end_pos or (pos - 1)] or sp
            anchor_n = anchor_n + 1
            anchors[anchor_n] = {
                anchor = C.AnchorRef(tostring(node)),
                range = C.LspRange(
                    C.LspPos((sp.line or 1) - 1, (sp.col or 1) - 1),
                    C.LspPos((ep.line or 1) - 1, (ep.col or 1) - 1 + ((ep.end_offset or ep.start_offset or 1) - (ep.start_offset or 1) + 1))
                ),
                start_pos = start_pos,
                end_pos = end_pos or (pos - 1),
            }
            return node
        end

        local parse_expr, parse_block, parse_stmt
        local lvalue_to_expr

        local function span_from_token_positions(start_pos, end_pos)
            local sp = positions[start_pos] or { line = 1, col = 1, start_offset = 1, end_offset = 1 }
            local ep = positions[end_pos or start_pos] or sp
            return C.Span(
                C.LspRange(
                    C.LspPos((sp.line or 1) - 1, (sp.col or 1) - 1),
                    C.LspPos((ep.line or 1) - 1, (ep.col or 1) - 1 + ((ep.end_offset or ep.start_offset or 1) - (ep.start_offset or 1) + 1))
                ),
                sp.start_offset or 1,
                ep.end_offset or ep.start_offset or 1
            )
        end

        local function parse_name()
            local p0 = pos
            local t = expect("<name>")
            return mark_range(C.Name(t.value), p0)
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
                    advance()
                    local val = parse_expr()
                    fields[#fields + 1] = mark_range(C.NameField(name, val), p0)
                elseif check("}") then
                    break
                else
                    local val = parse_expr()
                    fields[#fields + 1] = mark_range(C.ArrayField(val), p0)
                end
                if not match(",") then
                    match(";")
                    if check("}") then break end
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
                error(string.format("parse error at token %d: unexpected '%s' in expression", pos, k), 0)
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
                advance(); return C.Nil
            elseif k == "true" then
                advance(); return mark_range(C.True, p0)
            elseif k == "false" then
                advance(); return mark_range(C.False, p0)
            elseif k == "..." then
                advance(); return mark_range(C.Vararg, p0)
            elseif k == "function" then
                advance(); return mark_range(C.FunctionExpr(parse_funcbody()), p0)
            elseif k == "{" then
                advance()
                local fields = parse_fieldlist()
                expect("}")
                return mark_range(C.TableCtor(fields), p0)
            else
                return parse_suffixed_expr()
            end
        end

        local UNARY_OPS = { ["-"] = true, ["not"] = true, ["#"] = true, ["~"] = true }
        local BINARY_PREC = {
            ["or"]  = {1, 1}, ["and"] = {2, 2},
            ["<"] = {3, 3}, [">"] = {3, 3}, ["<="] = {3, 3}, [">="] = {3, 3}, ["~="] = {3, 3}, ["=="] = {3, 3},
            ["|"] = {4, 4}, ["~"] = {5, 5}, ["&"] = {6, 6},
            ["<<"] = {7, 7}, [">>"] = {7, 7},
            [".."] = {8, 7},
            ["+"] = {9, 9}, ["-"] = {9, 9},
            ["*"] = {10, 10}, ["/"] = {10, 10}, ["//"] = {10, 10}, ["%"] = {10, 10},
            ["^"] = {12, 11},
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

        parse_expr = function() return parse_binary(1) end

        local function parse_exprlist()
            local exprs = { parse_expr() }
            while match(",") do exprs[#exprs + 1] = parse_expr() end
            return exprs
        end

        local function expr_to_lvalue(expr)
            if expr.kind == "NameRef" then return C.LName(expr.name) end
            if expr.kind == "Field" then return C.LField(expr.base, expr.key) end
            if expr.kind == "Index" then return C.LIndex(expr.base, expr.key) end
            return C.LName("_")
        end

        lvalue_to_expr = function(lv)
            if lv.kind == "LName" then return C.NameRef(lv.name) end
            if lv.kind == "LField" then return C.Field(lv.base, lv.key) end
            if lv.kind == "LIndex" then return C.Index(lv.base, lv.key) end
            return C.NameRef("_")
        end

        local function parse_if_stmt()
            local p0 = pos
            advance()
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
            if match("else") then else_block = parse_block() end
            expect("end")
            return mark_range(C.If(arms, else_block), p0)
        end

        local function parse_while_stmt()
            local p0 = pos
            advance()
            local cond = parse_expr()
            expect("do")
            local body = parse_block()
            expect("end")
            return mark_range(C.While(cond, body), p0)
        end

        local function parse_repeat_stmt()
            local p0 = pos
            advance()
            local body = parse_block()
            expect("until")
            local cond = parse_expr()
            return mark_range(C.Repeat(body, cond), p0)
        end

        local function parse_for_stmt()
            local p0 = pos
            advance()
            local name = expect("<name>").value
            if match("=") then
                local init = parse_expr()
                expect(",")
                local limit = parse_expr()
                local step = check(",") and (advance() and parse_expr()) or C.Number("1")
                expect("do")
                local body = parse_block()
                expect("end")
                return mark_range(C.ForNum(name, init, limit, step, body), p0)
            else
                local names = { mark_range(C.Name(name), p0 + 1) }
                while match(",") do names[#names + 1] = parse_name() end
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
            advance()
            if match("function") then
                local fname = expect("<name>").value
                local body = parse_funcbody()
                return mark_range(C.LocalFunction(fname, body), p0)
            end
            local names = { parse_name() }
            while match(",") do names[#names + 1] = parse_name() end
            local values = {}
            if match("=") then values = parse_exprlist() end
            return mark_range(C.LocalAssign(names, values), p0)
        end

        local function parse_function_stmt()
            local p0 = pos
            advance()
            local fname_p0 = pos
            local name_str = expect("<name>").value
            local lv = mark_range(C.LName(name_str), fname_p0)
            while match(".") do
                local key = expect("<name>").value
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
            advance()
            local values = {}
            local k = peek_kind()
            if k ~= "end" and k ~= "else" and k ~= "elseif" and k ~= "until" and k ~= "<eof>" and k ~= ";" then
                values = parse_exprlist()
            end
            match(";")
            return mark_range(C.Return(values), p0)
        end

        parse_stmt = function()
            local p0 = pos
            local k = peek_kind()
            if k == "if" then return parse_if_stmt()
            elseif k == "while" then return parse_while_stmt()
            elseif k == "repeat" then return parse_repeat_stmt()
            elseif k == "for" then return parse_for_stmt()
            elseif k == "do" then
                advance(); local body = parse_block(); expect("end"); return mark_range(C.Do(body), p0)
            elseif k == "local" then return parse_local_stmt()
            elseif k == "function" then return parse_function_stmt()
            elseif k == "return" then return parse_return_stmt()
            elseif k == "break" then advance(); return mark_range(C.Break, p0)
            elseif k == "goto" then advance(); return mark_range(C.Goto(expect("<name>").value), p0)
            elseif k == "::" then advance(); local label = expect("<name>").value; expect("::"); return mark_range(C.Label(label), p0)
            elseif k == ";" then advance(); return nil
            else
                local expr = parse_suffixed_expr()
                if check("=") or check(",") then
                    local lhs = { expr_to_lvalue(expr) }
                    while match(",") do lhs[#lhs + 1] = expr_to_lvalue(parse_suffixed_expr()) end
                    expect("=")
                    local rhs = parse_exprlist()
                    return mark_range(C.Assign(lhs, rhs), p0)
                end
                if expr.kind == "Call" or expr.kind == "MethodCall" then
                    return mark_range(C.CallStmt(expr.callee or expr.recv, expr.args or {}), p0)
                end
                return mark_range(C.CallStmt(expr, {}), p0)
            end
        end

        local function parse_doc_comment(text)
            local tags = {}
            local primitive = { number = C.TNumber, string = C.TString, boolean = C.TBoolean, ["nil"] = C.TNil, any = C.TAny }
            local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end
            local function parse_doc_type(s)
                s = trim(s)
                if s == "" then return C.TAny end
                local parts = {}
                for raw in s:gmatch("[^|]+") do
                    local p = trim(raw)
                    local optional = false
                    if p:sub(-1) == "?" then optional = true; p = p:sub(1, -2) end
                    local arr = 0
                    while p:sub(-2) == "[]" do arr = arr + 1; p = p:sub(1, -3) end
                    local t = primitive[p] or C.TNamed(p)
                    for _ = 1, arr do t = C.TArray(t) end
                    if optional then t = C.TOptional(t) end
                    parts[#parts + 1] = t
                end
                if #parts == 0 then return C.TAny end
                if #parts == 1 then return parts[1] end
                return C.TUnion(parts)
            end

            local cls, extends = text:match("%-%-%-@class%s+([%w_%.]+)%s*:%s*(.+)")
            if cls then
                local ex = {}
                for e in tostring(extends or ""):gmatch("[^,]+") do ex[#ex + 1] = parse_doc_type(e) end
                tags[#tags + 1] = C.ClassTag(cls, ex)
                return tags
            end
            cls = text:match("%-%-%-@class%s+([%w_%.]+)")
            if cls then tags[#tags + 1] = C.ClassTag(cls, {}); return tags end

            local fname, fopt_name, ftype = text:match("%-%-%-@field%s+([%w_]+)(%??)%s+([%w_%.%[%]%|%?]+)")
            if fname then tags[#tags + 1] = C.FieldTag(fname, parse_doc_type(ftype), fopt_name == "?"); return tags end

            local pname, ptype = text:match("%-%-%-@param%s+([%w_]+)%s+([%w_%.%[%]%|%?]+)")
            if pname then tags[#tags + 1] = C.ParamTag(pname, parse_doc_type(ptype)); return tags end

            local rtype = text:match("%-%-%-@return%s+([%w_%.%[%]%|%?]+)")
            if rtype then tags[#tags + 1] = C.ReturnTag({ parse_doc_type(rtype) }); return tags end

            local aname, atype = text:match("%-%-%-@alias%s+([%w_%.]+)%s+([%w_%.%[%]%|%?]+)")
            if aname then tags[#tags + 1] = C.AliasTag(aname, parse_doc_type(atype)); return tags end

            local ttype = text:match("%-%-%-@type%s+([%w_%.%[%]%|%?]+)")
            if ttype then tags[#tags + 1] = C.TypeTag(parse_doc_type(ttype)); return tags end

            local gname = text:match("%-%-%-@generic%s+([%w_]+)")
            if gname then tags[#tags + 1] = C.GenericTag(gname, {}); return tags end

            local ctype = text:match("%-%-%-@cast%s+%w+%s+([%w_%.%[%]%|%?]+)")
            if ctype then tags[#tags + 1] = C.CastTag(parse_doc_type(ctype)); return tags end

            local mname, mtext = text:match("%-%-%-@(%w+)%s+(.*)")
            if mname then tags[#tags + 1] = C.MetaTag(mname, mtext); return tags end
            return tags
        end

        parse_block = function()
            block_depth = block_depth + 1
            local is_top = (block_depth == 1)
            local items = {}
            local pending_tags = {}
            local pending_start = nil
            while true do
                local k = raw_peek_kind()
                if k == "end" or k == "else" or k == "elseif" or k == "until" or k == "<eof>" then break end
                if k == "<comment>" then
                    local at = pos
                    local t = raw_advance()
                    if t.value:match("^%-%-%-@") then
                        if not pending_start then pending_start = at end
                        local tags = parse_doc_comment(t.value)
                        for j = 1, #tags do
                            local tag = tags[j]
                            mark_range(tag, at)
                            pending_tags[#pending_tags + 1] = tag
                        end
                    end
                else
                    local item_start = pending_start or pos
                    local ok, stmt = pcall(parse_stmt)
                    if ok and stmt then
                        local docs = {}
                        if #pending_tags > 0 then docs[1] = C.DocBlock(pending_tags); pending_tags = {} end
                        items[#items + 1] = C.Item(docs, stmt)
                        if is_top then
                            top_items[#top_items + 1] = {
                                index = #items,
                                start_pos = item_start,
                                end_pos = pos - 1,
                            }
                        end
                        pending_start = nil
                    elseif not ok then
                        raw_advance()
                        pending_tags = {}
                        pending_start = nil
                    end
                end
            end
            block_depth = block_depth - 1
            return C.Block(items)
        end

        local function parse_doc(source)
            local block = parse_block()
            local core_items = block.items
            if #core_items == 0 then
                core_items = { C.Item({}, C.Break) }
                top_items = { { index = 1, start_pos = 1, end_pos = 1 } }
            end

            local anchor_points = {}
            for i = 1, anchor_n do
                local a = anchors[i]
                local sp = positions[a.start_pos] or { start_offset = 1 }
                local ep = positions[a.end_pos] or sp
                anchor_points[i] = C.AnchorPoint(
                    a.anchor,
                    "",
                    C.Span(
                        a.range,
                        sp.start_offset or 1,
                        ep.end_offset or ep.start_offset or 1
                    )
                )
            end

            local items = {}
            for i = 1, #top_items do
                local it = top_items[i]
                items[i] = C.LocatedItem(core_items[it.index], span_from_token_positions(it.start_pos, it.end_pos))
            end

            return C.ParsedDoc(source.uri, source.version or 0, source.text or "", items, anchor_points, C.ParseOk)
        end

        return { parse_doc = parse_doc }
    end

    local function error_doc(source, message)
        return C.ParsedDoc(source.uri, source.version or 0, source.text or "", {}, {}, C.ParseError(tostring(message or "parse error")))
    end

    local function parse_source(source, base_line, base_col, base_offset)
        local lexed = pvm.drain(lexer_engine.lex_with_positions(source))
        local tokens = {}
        local positions = {}
        local bl = base_line or 1
        local bc = base_col or 1
        local bo = base_offset or 1
        for i = 1, #lexed do
            local lt = lexed[i]
            tokens[i] = lt.token
            positions[i] = {
                line = bl + lt.line - 1,
                col = (lt.line == 1) and (bc + lt.col - 1) or lt.col,
                start_offset = bo + lt.start_offset - 1,
                end_offset = bo + lt.end_offset - 1,
            }
        end

        local ok, parser = pcall(make_parser, tokens, positions, source.uri)
        if not ok then return error_doc(source, parser) end

        local ok2, doc = pcall(function() return parser.parse_doc(source) end)
        if not ok2 then return error_doc(source, doc) end
        return doc
    end

    local parse = pvm.phase("parse", function(source)
        return parse_source(source, 1, 1, 1)
    end)

    local function range_from_offsets(text, start_offset, stop_offset)
        local sl, sc = offset_to_line_col(text, start_offset)
        local el, ec = offset_to_line_col(text, (stop_offset or start_offset) + 1)
        return C.LspRange(C.LspPos(sl - 1, sc - 1), C.LspPos(el - 1, ec - 1))
    end

    local function shift_span(span, delta, text)
        if not span then
            return C.Span(C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1)), 1, 1)
        end
        if (delta or 0) == 0 then return span end
        local so = (span.start_offset or 1) + delta
        local eo = (span.stop_offset or so) + delta
        return C.Span(range_from_offsets(text, so, eo), so, eo)
    end

    local function shift_item(item, delta, text)
        if not item then return nil end
        if (delta or 0) == 0 then return item end
        return C.LocatedItem(item.core, shift_span(item.span, delta or 0, text))
    end

    local function slice_items(doc, start_idx, end_idx, delta, text)
        local out = {}
        if not doc or not doc.items then return out end
        for i = start_idx or 1, end_idx or 0 do
            local it = doc.items[i]
            if it then out[#out + 1] = shift_item(it, delta, text) end
        end
        return out
    end

    local function slice_anchor_range(doc, start_offset, stop_offset, delta, text)
        local out = {}
        if not doc or not doc.anchors then return out end
        for i = 1, #doc.anchors do
            local ap = doc.anchors[i]
            local sp = ap.span
            if sp and sp.start_offset >= start_offset and sp.stop_offset <= stop_offset then
                if (delta or 0) == 0 then
                    out[#out + 1] = ap
                else
                    out[#out + 1] = C.AnchorPoint(ap.anchor, ap.label, shift_span(ap.span, delta, text))
                end
            end
        end
        return out
    end

    local function concat3(a, b, c)
        local out = {}
        for i = 1, #a do out[#out + 1] = a[i] end
        for i = 1, #b do out[#out + 1] = b[i] end
        for i = 1, #c do out[#out + 1] = c[i] end
        return out
    end

    local function parse_incremental(uri, version, text, prev_doc)
        local source = C.OpenDoc(uri, version or 0, text or "")
        if not prev_doc then
            return pvm.one(parse(source))
        end

        local old_items = prev_doc.items or {}
        local old_text = prev_doc.text or ""
        local new_text = text or ""
        if #old_items == 0 then
            return pvm.one(parse(source))
        end

        if old_text == new_text then
            return C.ParsedDoc(source.uri, source.version or 0, source.text or "", slice_items(prev_doc, 1, #old_items, 0, source.text or ""), prev_doc.anchors, prev_doc.status)
        end

        local old_len, new_len = #old_text, #new_text
        local prefix = 0
        local max_prefix = math.min(old_len, new_len)
        while prefix < max_prefix and old_text:byte(prefix + 1) == new_text:byte(prefix + 1) do
            prefix = prefix + 1
        end

        local suffix = 0
        local max_suffix = math.min(old_len - prefix, new_len - prefix)
        while suffix < max_suffix and old_text:byte(old_len - suffix) == new_text:byte(new_len - suffix) do
            suffix = suffix + 1
        end

        local old_change_start = prefix + 1
        local old_change_end = math.max(old_change_start, old_len - suffix)
        local delta = new_len - old_len

        local first_idx, last_idx = nil, nil
        for i = 1, #old_items do
            local sp = old_items[i].span
            if sp and sp.stop_offset >= old_change_start then first_idx = i; break end
        end
        for i = #old_items, 1, -1 do
            local sp = old_items[i].span
            if sp and sp.start_offset <= old_change_end then last_idx = i; break end
        end
        if not first_idx or not last_idx or first_idx > last_idx then
            return pvm.one(parse(source))
        end

        local region_start = old_items[first_idx].span.start_offset
        local old_suffix_start = (last_idx < #old_items) and old_items[last_idx + 1].span.start_offset or (old_len + 1)
        local new_suffix_start = old_suffix_start + delta
        if new_suffix_start < region_start then new_suffix_start = region_start end

        local start_line, start_col = offset_to_line_col(new_text, region_start)
        local region_text = new_text:sub(region_start, new_suffix_start - 1)
        local mid_doc = C.ParsedDoc(uri, version or 0, region_text, {}, {}, C.ParseOk)
        if region_text ~= "" then
            mid_doc = parse_source(C.OpenDoc(uri, version or 0, region_text), start_line, start_col, region_start)
            if mid_doc.status.kind == "ParseError" then
                return pvm.one(parse(source))
            end
        end

        local prefix_items = slice_items(prev_doc, 1, first_idx - 1, 0, new_text)
        local suffix_items = slice_items(prev_doc, last_idx + 1, #old_items, delta, new_text)
        local prefix_anchors = slice_anchor_range(prev_doc, 1, region_start - 1, 0, new_text)
        local suffix_anchors = slice_anchor_range(prev_doc, old_suffix_start, old_len + 1, delta, new_text)

        return C.ParsedDoc(
            source.uri,
            source.version or 0,
            source.text or "",
            concat3(prefix_items, mid_doc.items or {}, suffix_items),
            concat3(prefix_anchors, mid_doc.anchors or {}, suffix_anchors),
            C.ParseOk
        )
    end

    return {
        C = C,
        context = ctx,
        lexer = lexer_engine,
        parse = parse,
        parse_incremental = parse_incremental,
    }
end

return M
