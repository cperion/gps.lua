-- lsp/editor.lua
--
-- Editor-facing feature planning over ParsedDoc.
--
-- Boundaries:
--   InlayHintQuery      -> LspInlayHintList
--   FoldingRangeQuery   -> LspFoldingRangeList
--   SelectionRangeQuery -> LspSelectionRangeList
--   CodeLensQuery       -> LspCodeLensList
--   ColorQuery          -> LspColorInfoList

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

local function utf8_char_len_at(s, i)
    local b = s:byte(i)
    if not b then return 0 end
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

local function line_bounds(text, line0)
    local line = line0 or 0
    if line < 0 then line = 0 end
    local pos, cur = 1, 0
    while cur < line do
        local nl = text:find("\n", pos, true)
        if not nl then return #text + 1, #text + 1 end
        pos = nl + 1
        cur = cur + 1
    end
    local line_end = text:find("\n", pos, true)
    if not line_end then line_end = #text + 1 end
    return pos, line_end
end

local function utf16_len(s)
    local n, i = 0, 1
    while i <= #s do
        local len = utf8_char_len_at(s, i)
        if len <= 0 then len = 1 end
        if i + len - 1 > #s then len = 1 end
        n = n + ((len == 4) and 2 or 1)
        i = i + len
    end
    return n
end

local function byte_to_utf16_col_in_line(line_text, byte_index)
    local target = byte_index or 1
    if target < 1 then target = 1 end
    if target > #line_text + 1 then target = #line_text + 1 end
    local col, i = 0, 1
    while i < target do
        local len = utf8_char_len_at(line_text, i)
        if len <= 0 then len = 1 end
        if i + len - 1 > #line_text then len = 1 end
        col = col + ((len == 4) and 2 or 1)
        i = i + len
    end
    return col
end

local function pos_leq(a, b)
    if a.line ~= b.line then return a.line < b.line end
    return a.character <= b.character
end

local function position_in_range(pos, r)
    if not pos or not r or not r.start or not r.stop then return false end
    return pos_leq(r.start, pos) and pos_leq(pos, r.stop)
end

local function range_size_key(r)
    if not r or not r.start or not r.stop then return math.huge end
    local dl = (r.stop.line or 0) - (r.start.line or 0)
    local dc = (r.stop.character or 0) - (r.start.character or 0)
    if dc < 0 then dc = 0 end
    return dl * 100000 + dc
end

local function split_lines(text)
    local raw_lines = {}
    local n = 0
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        raw_lines[n] = line
    end
    if n > 0 then n = n - 1 end
    return raw_lines, n
end

function M.new(ctx, opts)
    opts = opts or {}
    local C = ctx.Lua
    local type_engine = opts.type_engine
    local lexer_engine = opts.lexer_engine

    local function range_for(doc, anchor)
        if opts.range_for then return opts.range_for(doc, anchor) end
        return C.LspRange(C.LspPos(0, 0), C.LspPos(0, 1))
    end

    local function all_anchor_entries(doc)
        if opts.all_anchor_entries then return opts.all_anchor_entries(doc) end
        return {}
    end

    local inlay_hints = pvm.phase("inlay_hints", function(q)
        local doc = q.doc
        local out, seen = {}, {}

        local function add_hint_for_anchor(anchor, tstr)
            if not anchor or not tstr or tstr == "" or tstr == "any" or tstr == "unknown" then return end
            local r = range_for(doc, anchor)
            local pos = C.LspPos(r.stop.line, r.stop.character)
            if not position_in_range(pos, q.range) then return end
            local key = pos.line .. ":" .. pos.character .. ":" .. tstr
            if seen[key] then return end
            seen[key] = true
            out[#out + 1] = C.LspInlayHint(pos, ": " .. tstr, C.InlayType)
        end

        if type_engine then
            local ti = pvm.one(type_engine.typed_index(doc))
            for i = 1, #ti.symbols do
                local ts = ti.symbols[i]
                local sym = ts.symbol
                if sym and sym.decl_anchor and (sym.kind == C.SymLocal or sym.kind == C.SymParam) then
                    add_hint_for_anchor(sym.decl_anchor, type_engine.type_to_string(ts.typ))
                end
            end
        end

        local function expr_type_name(e)
            if not e then return nil end
            if e.kind == "Number" then return "number" end
            if e.kind == "String" then return "string" end
            if e.kind == "True" or e.kind == "False" then return "boolean" end
            if e.kind == "Nil" then return "nil" end
            if e.kind == "TableCtor" then return "table" end
            if e.kind == "FunctionExpr" or e.kind == "LocalFunction" then return "fun" end
            return nil
        end

        for i = 1, #doc.items do
            local s = doc.items[i].core.stmt
            if s.kind == "LocalAssign" then
                for j = 1, #s.names do
                    add_hint_for_anchor(C.AnchorRef(tostring(s.names[j])), expr_type_name(s.values[j]))
                end
            elseif s.kind == "LocalFunction" then
                add_hint_for_anchor(C.AnchorRef(tostring(s)), "fun")
            end
        end

        table.sort(out, function(a, b)
            if a.position.line ~= b.position.line then return a.position.line < b.position.line end
            return a.position.character < b.position.character
        end)

        return C.LspInlayHintList(out)
    end)

    local folding_ranges = pvm.phase("folding_ranges", function(q)
        local doc = q.doc
        local lines, n = split_lines(doc.text or "")
        local out, seen = {}, {}

        local function add_fold(line0s, line0e, kind, scol, ecol)
            if not line0s or not line0e or line0e <= line0s then return end
            local end_line_text = lines[line0e + 1] or ""
            local ec = ecol or byte_to_utf16_col_in_line(end_line_text, #end_line_text + 1)
            local key = line0s .. ":" .. line0e .. ":" .. tostring(kind)
            if seen[key] then return end
            seen[key] = true
            out[#out + 1] = C.LspFoldingRange(line0s, scol or 0, line0e, ec, kind or C.FoldRegion)
        end

        for i = 1, #doc.items do
            local s = doc.items[i].core.stmt
            local k = s and s.kind or ""
            if k == "If" or k == "While" or k == "Repeat" or k == "ForNum" or k == "ForIn"
                or k == "Do" or k == "Function" or k == "LocalFunction" then
                local r = range_for(doc, C.AnchorRef(tostring(s)))
                if r and r.start and r.stop then
                    add_fold(r.start.line, r.stop.line, C.FoldRegion, r.start.character, r.stop.character)
                end
            end
        end

        local comment_start = nil
        for i = 1, n do
            local s = (lines[i] or ""):match("^%s*(.-)%s*$")
            if s:match("^%-%-") then
                if not comment_start then comment_start = i end
            else
                if comment_start and (i - comment_start) >= 2 then add_fold(comment_start - 1, i - 2, C.FoldComment, 0, nil) end
                comment_start = nil
            end
        end
        if comment_start and (n - comment_start + 1) >= 2 then add_fold(comment_start - 1, n - 1, C.FoldComment, 0, nil) end

        table.sort(out, function(a, b)
            if a.start_line ~= b.start_line then return a.start_line < b.start_line end
            if a.end_line ~= b.end_line then return a.end_line < b.end_line end
            return a.start_character < b.start_character
        end)

        return C.LspFoldingRangeList(out)
    end)

    local selection_ranges = pvm.phase("selection_ranges", function(q)
        local doc = q.doc
        local entries = all_anchor_entries(doc) or {}
        local out = {}

        for i = 1, #q.positions do
            local p = q.positions[i]
            local pos = C.LspPos(p.line, p.character)
            local hits = {}
            for j = 1, #entries do
                local e = entries[j]
                if position_in_range(pos, e.range) then hits[#hits + 1] = e.range end
            end
            table.sort(hits, function(a, b) return range_size_key(a) < range_size_key(b) end)

            if #hits > 0 then
                local primary = hits[1]
                local parents = {}
                for j = 2, #hits do parents[#parents + 1] = hits[j] end
                out[#out + 1] = C.LspSelectionRange(primary, parents)
            else
                local line_start, line_end = line_bounds(doc.text or "", p.line)
                local line_text = (doc.text or ""):sub(line_start, line_end - 1)
                local bi = 1
                do
                    local target = p.character or 0
                    local count, k = 0, 1
                    while k <= #line_text do
                        if target <= count then bi = k break end
                        local len = utf8_char_len_at(line_text, k)
                        if len <= 0 then len = 1 end
                        if k + len - 1 > #line_text then len = 1 end
                        local units = (len == 4) and 2 or 1
                        if target < count + units then bi = k break end
                        count = count + units
                        k = k + len
                        bi = k
                    end
                    if bi > #line_text then bi = #line_text end
                    if bi < 1 then bi = 1 end
                end
                local l, r = bi, bi
                local function ident(ch) return ch and ch:match("[%w_]") ~= nil end
                if #line_text > 0 and not ident(line_text:sub(bi, bi)) and bi > 1 and ident(line_text:sub(bi - 1, bi - 1)) then l, r = bi - 1, bi - 1 end
                if #line_text > 0 and ident(line_text:sub(l, l)) then
                    while l > 1 and ident(line_text:sub(l - 1, l - 1)) do l = l - 1 end
                    while r < #line_text and ident(line_text:sub(r + 1, r + 1)) do r = r + 1 end
                end
                local sc = byte_to_utf16_col_in_line(line_text, l)
                local ec = byte_to_utf16_col_in_line(line_text, r + 1)
                if ec < sc then ec = sc end
                local rr = C.LspRange(C.LspPos(p.line, sc), C.LspPos(p.line, ec))
                local line_rr = C.LspRange(C.LspPos(p.line, 0), C.LspPos(p.line, byte_to_utf16_col_in_line(line_text, #line_text + 1)))
                out[#out + 1] = C.LspSelectionRange(rr, { line_rr })
            end
        end

        return C.LspSelectionRangeList(out)
    end)

    local code_lenses = pvm.phase("code_lenses", function(q)
        local doc = q.doc
        local out = {}
        for i = 1, #doc.items do
            local s = doc.items[i].core.stmt
            if s and (s.kind == "Function" or s.kind == "LocalFunction") then
                local r = range_for(doc, C.AnchorRef(tostring(s)))
                out[#out + 1] = C.LspCodeLens(C.LspRange(C.LspPos(r.start.line, 0), C.LspPos(r.start.line, 1)), "Run solve", "lua.solve")
            end
        end
        return C.LspCodeLensList(out)
    end)

    local document_colors = pvm.phase("document_colors", function(q)
        local doc = q.doc
        if not lexer_engine or not lexer_engine.lex_with_positions then return C.LspColorInfoList({}) end
        local out, seen = {}, {}
        local text = doc.text or ""
        local src = C.OpenDoc(doc.uri, doc.version or 0, text)
        local lexed = pvm.drain(lexer_engine.lex_with_positions(src))

        local function add_color(line0, startc, endc, r, g, b, a)
            local key = line0 .. ":" .. startc .. ":" .. endc
            if seen[key] then return end
            seen[key] = true
            out[#out + 1] = C.LspColorInfo(C.LspRange(C.LspPos(line0, startc), C.LspPos(line0, endc)), C.LspColor(r / 255, g / 255, b / 255, a / 255))
        end

        for i = 1, #lexed do
            local lt = lexed[i]
            local tok = lt.token
            if tok and tok.kind == "<number>" then
                local v = tostring(tok.value or ""):gsub("_", "")
                v = v:gsub("[uUlLiI]+$", "")
                local rr, gg, bb, aa = v:match("^0[xX](%x%x)(%x%x)(%x%x)(%x%x)$")
                if rr and gg and bb and aa then
                    local line0 = (lt.line or 1) - 1
                    local line_start = line_bounds(text, line0)
                    local start_off = lt.start_offset or line_start
                    local stop_off = lt.end_offset or start_off
                    if stop_off < start_off then stop_off = start_off end
                    local prefix = text:sub(line_start, math.max(line_start, start_off) - 1)
                    local token_txt = text:sub(start_off, stop_off)
                    local startc = utf16_len(prefix)
                    local endc = startc + utf16_len(token_txt)
                    add_color(line0, startc, endc, tonumber(rr, 16), tonumber(gg, 16), tonumber(bb, 16), tonumber(aa, 16))
                end
            end
        end

        return C.LspColorInfoList(out)
    end)

    return {
        inlay_hints_phase = inlay_hints,
        folding_ranges_phase = folding_ranges,
        selection_ranges_phase = selection_ranges,
        code_lenses_phase = code_lenses,
        document_colors_phase = document_colors,
        inlay_hints = inlay_hints,
        folding_ranges = folding_ranges,
        selection_ranges = selection_ranges,
        code_lenses = code_lenses,
        document_colors = document_colors,
        C = C,
    }
end

return M
