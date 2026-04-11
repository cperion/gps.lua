-- bench/lua_lsp_parser_treesitter_nvim_v1.lua
--
-- Real Lua parser adapter using Neovim's Tree-sitter Lua parser.
--
-- Provides callbacks compatible with lua_lsp_server_core_v1:
--   parse(uri, text, prev_file, C, params) -> file_ast, meta
--   position_to_anchor(file, position, doc, adapter, params) -> anchor
--   anchor_to_range(file, anchor) -> LSP range

package.path = "./?.lua;./?/init.lua;" .. package.path

local JsonRpc = require("bench.lua_lsp_jsonrpc_v1")

local M = {}

local function split_lines(text)
    local out = {}
    text = text or ""
    if text == "" then return { "" } end
    text = text:gsub("\r\n", "\n")
    local i = 1
    while true do
        local j = text:find("\n", i, true)
        if not j then
            out[#out + 1] = text:sub(i)
            break
        end
        out[#out + 1] = text:sub(i, j - 1)
        i = j + 1
    end
    return out
end

local function slice_range(lines, r)
    local sr, sc, er, ec = r[1], r[2], r[3], r[4]
    local sline = lines[sr + 1] or ""
    if sr == er then
        return sline:sub(sc + 1, ec)
    end

    local parts = {}
    parts[#parts + 1] = sline:sub(sc + 1)
    for i = sr + 2, er do
        parts[#parts + 1] = lines[i] or ""
    end
    parts[#parts + 1] = (lines[er + 1] or ""):sub(1, ec)
    return table.concat(parts, "\n")
end

local function node_text(lines, node)
    return slice_range(lines, node.range)
end

local function named_children(node)
    local out = {}
    local ch = node.children or {}
    for i = 1, #ch do
        if ch[i].named then out[#out + 1] = ch[i] end
    end
    return out
end

local function first_named_child_of_type(node, t)
    local ch = node.children or {}
    for i = 1, #ch do
        local c = ch[i]
        if c.named and c.type == t then return c end
    end
    return nil
end

local function named_children_of_type(node, t)
    local out = {}
    local ch = node.children or {}
    for i = 1, #ch do
        local c = ch[i]
        if c.named and c.type == t then out[#out + 1] = c end
    end
    return out
end

local function has_child_type(node, t)
    local ch = node.children or {}
    for i = 1, #ch do
        if ch[i].type == t then return true end
    end
    return false
end

local function pick_op(node, lines)
    local ch = node.children or {}
    for i = 1, #ch do
        local c = ch[i]
        if not c.named then
            local txt = node_text(lines, c)
            if txt and txt ~= "" then return txt end
        end
    end
    return "?"
end

local function run_nvim_dump(source, dump_script)
    local tmp = os.tmpname()
    local f = assert(io.open(tmp, "wb"))
    f:write(source)
    f:close()

    local cmd = string.format("nvim --headless -u NONE -n -l %s %s 2>/dev/null",
        string.format("%q", dump_script),
        string.format("%q", tmp)
    )

    local p = assert(io.popen(cmd, "r"))
    local out = p:read("*a") or ""
    p:close()
    os.remove(tmp)

    out = out:gsub("^%s+", ""):gsub("%s+$", "")
    if out == "" then
        return nil, "empty nvim parse output"
    end

    local ok, obj = pcall(JsonRpc.json_decode, out)
    if not ok then
        return nil, "json decode failed: " .. tostring(obj)
    end
    if not obj.ok then
        return nil, obj.error or "nvim dump failed"
    end
    return obj.tree
end

function M.new(opts)
    opts = opts or {}

    local dump_script = opts.dump_script or "bench/lua_lsp_nvim_dump.lua"

    local function parse(uri, text, _prev_file, C, params)
        text = text or ""
        local lines = split_lines(text)

        local function range_from_node(node)
            if not node or not node.range then
                local p0 = C.Pos(0, 0)
                return C.Range(p0, p0, 0, 0)
            end
            local sr, sc, er, ec = node.range[1], node.range[2], node.range[3], node.range[4]
            local ps = C.Pos(sr, sc)
            local pe = C.Pos(er, ec)
            return C.Range(ps, pe, 0, 0)
        end

        local function server_meta_from_positions(positions, parse_error)
            local pts = {}
            for i = 1, #positions do
                local p = positions[i]
                local r = p.range
                pts[i] = C.ServerAnchorPoint(
                    C.AnchorRef(tostring(p.anchor)),
                    C.LspRange(
                        C.LspPos(r.start.line, r.start.character),
                        C.LspPos(r.stop.line, r.stop.character)
                    ),
                    ""
                )
            end
            return C.ServerMeta(pts, parse_error or "")
        end

        local function build_cst(node)
            if not node then
                return C.Cst("<nil>", range_from_node(nil), {})
            end
            local ch = node.children or {}
            local kids = {}
            for i = 1, #ch do
                kids[i] = build_cst(ch[i])
            end
            return C.Cst(node.type or "?", range_from_node(node), kids)
        end

        local root, err = run_nvim_dump(text, dump_script)
        if not root then
            -- hard fallback: valid File with one noop stmt so server stays alive
            local file = C.File(uri, { C.Item({}, C.Break()) })
            local p0 = C.Pos(0, 0)
            local r0 = C.Range(p0, p0, 0, 0)
            local cst = C.Cst("error", r0, {})
            local parse_forest = C.ParseForest(cst, {})
            local source = C.Source(text, {}, parse_forest)
            local version = (params and params.textDocument and params.textDocument.version) or 0
            local document = C.Document(uri, version, source, file, {})
            return file, server_meta_from_positions({}, tostring(err or ""))
        end

        local positions = {}
        local anchors = {}
        local function mark(anchor, node)
            local r = range_from_node(node)
            positions[#positions + 1] = {
                anchor = anchor,
                range = r,
            }
            anchors[#anchors + 1] = C.Anchor(anchor.kind or (node and node.type) or "node", tostring(anchor), r)
        end

        local function mk_doc_tags(comment_node)
            local txt = node_text(lines, comment_node)
            local tags = {}
            if not txt then return tags end

            local cls = txt:match("%-%-%-@class%s+([%w_%.]+)")
            if cls then
                local t = C.ClassTag(cls, {})
                mark(t, comment_node)
                tags[#tags + 1] = t
            end

            local alias = txt:match("%-%-%-@alias%s+([%w_%.]+)")
            if alias then
                local t = C.AliasTag(alias, C.Any())
                mark(t, comment_node)
                tags[#tags + 1] = t
            end

            local fname, ftyp = txt:match("%-%-%-@field%s+([%w_]+)%s+([%w_%.]+)")
            if fname then
                local typ = ({
                    number = C.TNumber(),
                    string = C.TString(),
                    boolean = C.TBoolean(),
                    ["nil"] = C.TNil(),
                    any = C.Any(),
                })[ftyp] or C.TNamed(ftyp or "any")
                local t = C.FieldTag(fname, typ, false)
                mark(t, comment_node)
                tags[#tags + 1] = t
            end

            return tags
        end

        local conv_expr, conv_stmt, conv_block, conv_lvalue, conv_args

        conv_lvalue = function(node)
            local t = node.type
            if t == "identifier" then
                local name = node_text(lines, node)
                local lv = C.LName(name)
                mark(lv, node)
                return lv
            elseif t == "dot_index_expression" then
                local nc = named_children(node)
                local base = conv_expr(nc[1] or node)
                local key = node_text(lines, nc[#nc] or node)
                local lv = C.LField(base, key)
                mark(lv, node)
                return lv
            elseif t == "index_expression" or t == "bracket_index_expression" then
                local nc = named_children(node)
                local base = conv_expr(nc[1] or node)
                local key = conv_expr(nc[2] or nc[1] or node)
                local lv = C.LIndex(base, key)
                mark(lv, node)
                return lv
            end
            -- fallback
            local txt = node_text(lines, node)
            local lv = C.LName(txt ~= "" and txt or "_")
            mark(lv, node)
            return lv
        end

        conv_args = function(args_node)
            local args = {}
            if not args_node then return args end
            local nc = named_children(args_node)
            for i = 1, #nc do args[#args + 1] = conv_expr(nc[i]) end
            return args
        end

        conv_expr = function(node)
            if not node then return C.Nil() end
            local t = node.type

            if t == "identifier" then
                local e = C.NameRef(node_text(lines, node))
                mark(e, node)
                return e
            elseif t == "number" then
                local e = C.Number(node_text(lines, node))
                mark(e, node)
                return e
            elseif t == "string" then
                local raw = node_text(lines, node)
                local e = C.String(raw)
                mark(e, node)
                return e
            elseif t == "nil" then
                return C.Nil()
            elseif t == "true" then
                local e = C.Bool(true)
                mark(e, node)
                return e
            elseif t == "false" then
                local e = C.Bool(false)
                mark(e, node)
                return e
            elseif t == "binary_expression" then
                local nc = named_children(node)
                local lhs = conv_expr(nc[1] or node)
                local rhs = conv_expr(nc[2] or node)
                local e = C.Binary(pick_op(node, lines), lhs, rhs)
                mark(e, node)
                return e
            elseif t == "unary_expression" then
                local nc = named_children(node)
                local e = C.Unary(pick_op(node, lines), conv_expr(nc[1] or node))
                mark(e, node)
                return e
            elseif t == "parenthesized_expression" then
                local nc = named_children(node)
                local e = C.Paren(conv_expr(nc[1] or node))
                mark(e, node)
                return e
            elseif t == "function_call" then
                local nc = named_children(node)
                local callee = conv_expr(nc[1] or node)
                local args = conv_args(first_named_child_of_type(node, "arguments") or nc[2])
                local e = C.Call(callee, args)
                mark(e, node)
                return e
            elseif t == "method_index_expression" then
                local nc = named_children(node)
                local recv = conv_expr(nc[1] or node)
                local meth = node_text(lines, nc[2] or node)
                local e = C.MethodCall(recv, meth, {})
                mark(e, node)
                return e
            elseif t == "dot_index_expression" then
                local nc = named_children(node)
                local base = conv_expr(nc[1] or node)
                local key = node_text(lines, nc[2] or node)
                local e = C.Field(base, key)
                mark(e, node)
                return e
            elseif t == "index_expression" or t == "bracket_index_expression" then
                local nc = named_children(node)
                local base = conv_expr(nc[1] or node)
                local key = conv_expr(nc[2] or node)
                local e = C.Index(base, key)
                mark(e, node)
                return e
            elseif t == "table_constructor" then
                local fields = {}
                local fns = named_children(node)
                for i = 1, #fns do
                    local fn = fns[i]
                    if fn.type == "field" then
                        local fch = named_children(fn)
                        if #fch == 1 then
                            local af = C.ArrayField(conv_expr(fch[1]))
                            mark(af, fn)
                            fields[#fields + 1] = af
                        elseif #fch >= 2 then
                            local pf = C.PairField(conv_expr(fch[1]), conv_expr(fch[2]))
                            mark(pf, fn)
                            fields[#fields + 1] = pf
                        end
                    else
                        local af = C.ArrayField(conv_expr(fn))
                        mark(af, fn)
                        fields[#fields + 1] = af
                    end
                end
                local e = C.TableCtor(fields)
                mark(e, node)
                return e
            elseif t == "function_definition" then
                local params_node = first_named_child_of_type(node, "parameters")
                local block_node = first_named_child_of_type(node, "block")
                local params = {}
                if params_node then
                    local pch = named_children(params_node)
                    for i = 1, #pch do
                        if pch[i].type == "identifier" then
                            local p = C.PName(node_text(lines, pch[i]))
                            mark(p, pch[i])
                            params[#params + 1] = p
                        end
                    end
                end
                local body = conv_block(block_node)
                local fb = C.FuncBody(params, has_child_type(params_node or { children = {} }, "...") or false, body)
                local e = C.FunctionExpr(fb)
                mark(e, node)
                return e
            end

            -- fallback: preserve identifier-like refs from unknown nodes
            local fallback_children = named_children(node)
            if #fallback_children > 0 then
                return conv_expr(fallback_children[1])
            end
            return C.Nil()
        end

        conv_block = function(block_node)
            local items = {}
            if not block_node then return C.Block(items) end
            local ch = named_children(block_node)
            for i = 1, #ch do
                local st = conv_stmt(ch[i])
                if st then items[#items + 1] = C.Item({}, st) end
            end
            return C.Block(items)
        end

        conv_stmt = function(node)
            local t = node.type

            if t == "variable_declaration" then
                local asg = first_named_child_of_type(node, "assignment_statement")
                if asg then
                    local vl = first_named_child_of_type(asg, "variable_list")
                    local el = first_named_child_of_type(asg, "expression_list")
                    local names, vals = {}, {}
                    if vl then
                        local ids = named_children_of_type(vl, "identifier")
                        for i = 1, #ids do
                            local nm = C.Name(node_text(lines, ids[i]))
                            mark(nm, ids[i])
                            names[#names + 1] = nm
                        end
                    end
                    if el then
                        local ex = named_children(el)
                        for i = 1, #ex do vals[#vals + 1] = conv_expr(ex[i]) end
                    end
                    return C.LocalAssign(names, vals)
                end
                return C.Break()
            end

            if t == "assignment_statement" then
                local vl = first_named_child_of_type(node, "variable_list")
                local el = first_named_child_of_type(node, "expression_list")
                local lhs, rhs = {}, {}
                if vl then
                    local lv = named_children(vl)
                    for i = 1, #lv do lhs[#lhs + 1] = conv_lvalue(lv[i]) end
                end
                if el then
                    local ex = named_children(el)
                    for i = 1, #ex do rhs[#rhs + 1] = conv_expr(ex[i]) end
                end
                return C.Assign(lhs, rhs)
            end

            if t == "function_declaration" then
                local is_local = has_child_type(node, "local")
                local params_node = first_named_child_of_type(node, "parameters")
                local block_node = first_named_child_of_type(node, "block")

                local params = {}
                if params_node then
                    local pch = named_children(params_node)
                    for i = 1, #pch do
                        if pch[i].type == "identifier" then
                            local p = C.PName(node_text(lines, pch[i]))
                            mark(p, pch[i])
                            params[#params + 1] = p
                        end
                    end
                end

                local fb = C.FuncBody(params, has_child_type(params_node or { children = {} }, "...") or false, conv_block(block_node))

                local name_node = nil
                local nch = named_children(node)
                for i = 1, #nch do
                    if nch[i].type == "identifier" or nch[i].type == "dot_index_expression" or nch[i].type == "index_expression" or nch[i].type == "bracket_index_expression" then
                        name_node = nch[i]
                        break
                    end
                end

                if is_local and name_node and name_node.type == "identifier" then
                    return C.LocalFunction(node_text(lines, name_node), fb)
                end

                if name_node then
                    return C.Function(conv_lvalue(name_node), fb)
                end
                return C.Break()
            end

            if t == "function_call" then
                local nch = named_children(node)
                local callee = conv_expr(nch[1] or node)
                local args = conv_args(first_named_child_of_type(node, "arguments") or nch[2])
                return C.CallStmt(callee, args)
            end

            if t == "return_statement" then
                local el = first_named_child_of_type(node, "expression_list")
                local vals = {}
                if el then
                    local ex = named_children(el)
                    for i = 1, #ex do vals[#vals + 1] = conv_expr(ex[i]) end
                end
                return C.Return(vals)
            end

            if t == "if_statement" then
                local arms = {}
                local else_block = C.Block({})
                local ch = named_children(node)
                for i = 1, #ch do
                    local c = ch[i]
                    if c.type == "elseif_clause" or c.type == "if_clause" then
                        local cond = first_named_child_of_type(c, "expression") or named_children(c)[1]
                        local blk = first_named_child_of_type(c, "block")
                        arms[#arms + 1] = C.CondBlock(conv_expr(cond), conv_block(blk))
                    elseif c.type == "else_clause" then
                        else_block = conv_block(first_named_child_of_type(c, "block") or c)
                    end
                end
                if #arms == 0 then
                    local nc = named_children(node)
                    local cond = nc[1]
                    local blk = first_named_child_of_type(node, "block")
                    arms[1] = C.CondBlock(conv_expr(cond), conv_block(blk))
                end
                return C.If(arms, else_block)
            end

            if t == "while_statement" then
                local cond = first_named_child_of_type(node, "expression") or named_children(node)[1]
                local blk = first_named_child_of_type(node, "block")
                return C.While(conv_expr(cond), conv_block(blk))
            end

            if t == "repeat_statement" then
                local blk = first_named_child_of_type(node, "block")
                local cond = first_named_child_of_type(node, "expression") or named_children(node)[#named_children(node)]
                return C.Repeat(conv_block(blk), conv_expr(cond))
            end

            if t == "do_statement" then
                local blk = first_named_child_of_type(node, "block")
                return C.Do(conv_block(blk))
            end

            if t == "break_statement" then return C.Break() end
            if t == "goto_statement" then
                local id = first_named_child_of_type(node, "identifier")
                return C.Goto(id and node_text(lines, id) or "")
            end
            if t == "label_statement" then
                local id = first_named_child_of_type(node, "identifier")
                return C.Label(id and node_text(lines, id) or "")
            end

            -- generic fallback: try to preserve refs via expression conversion
            if node.named then
                local expr = conv_expr(node)
                if expr and expr.kind ~= "Nil" then
                    return C.CallStmt(C.NameRef("__expr"), { expr })
                end
            end
            return C.Break()
        end

        local items = {}
        local pending_tags = {}

        local top = named_children(root)
        for i = 1, #top do
            local n = top[i]
            if n.type == "comment" then
                local tags = mk_doc_tags(n)
                for j = 1, #tags do pending_tags[#pending_tags + 1] = tags[j] end
            else
                local stmt = conv_stmt(n)
                local docs = {}
                if #pending_tags > 0 then
                    local db = C.DocBlock(pending_tags)
                    mark(db, n)
                    docs[1] = db
                    pending_tags = {}
                end
                items[#items + 1] = C.Item(docs, stmt or C.Break())
            end
        end

        if #items == 0 then
            items[1] = C.Item({}, C.Break())
        end

        local file = C.File(uri, items)
        local cst_root = build_cst(root)
        local parse_forest = C.ParseForest(cst_root, {})
        local source = C.Source(text, {}, parse_forest)
        local version = (params and params.textDocument and params.textDocument.version) or 0
        local document = C.Document(uri, version, source, file, anchors)

        return file, server_meta_from_positions(positions, "")
    end

    local function anchor_to_range(_file, anchor, _aid, meta)
        if not anchor or not meta then return nil end
        local aid = anchor.id
        for i = 1, #meta.positions do
            local p = meta.positions[i]
            if p.anchor.id == aid then
                return {
                    start = { line = p.range.start.line, character = p.range.start.character },
                    ["end"] = { line = p.range.stop.line, character = p.range.stop.character },
                }
            end
        end
        return nil
    end

    local function position_to_anchor(_file, position, doc)
        local meta = doc and doc.meta
        if not meta then return nil end
        local line = position.line or 0
        local ch = position.character or 0
        for i = 1, #meta.positions do
            local p = meta.positions[i]
            local rs, re = p.range.start, p.range.stop
            if (line > rs.line or (line == rs.line and ch >= rs.character))
                and (line < re.line or (line == re.line and ch <= re.character)) then
                return p.anchor
            end
        end
        return nil
    end

    return {
        parse = parse,
        anchor_to_range = anchor_to_range,
        position_to_anchor = position_to_anchor,
    }
end

return M
