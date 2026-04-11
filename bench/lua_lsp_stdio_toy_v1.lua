#!/usr/bin/env luajit
-- lua_lsp_stdio_toy_v1.lua
--
-- JSON-RPC/LSP stdio entrypoint (toy parser) for quick integration testing.
--
-- Run manually with an editor/client that speaks LSP over stdio,
-- or with the test snippet in comments below.

package.path = "./?.lua;./?/init.lua;" .. package.path

local JsonRpc = require("bench.lua_lsp_jsonrpc_v1")

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

local function parse_toy(uri, text, _prev_file, C)
    local lines = split_lines(text)
    local items = {}
    local pending_tags = {}
    local positions = {}

    local function add_anchor(line0, start0, end0, anchor)
        positions[#positions + 1] = {
            line = line0,
            start = start0,
            ["end"] = end0,
            anchor = anchor,
        }
    end

    local function flush_item(stmt)
        local docs = {}
        if #pending_tags > 0 then
            docs[1] = C.DocBlock(pending_tags)
            pending_tags = {}
        end
        items[#items + 1] = C.Item(docs, stmt)
    end

    for li = 1, #lines do
        local line = lines[li]
        local line0 = li - 1

        local cname = line:match("^%-%-%-@class%s+([%w_%.]+)")
        if cname then
            local tag = C.ClassTag(cname, {})
            pending_tags[#pending_tags + 1] = tag
            local s = line:find(cname, 1, true) or 1
            add_anchor(line0, s - 1, s - 1 + #cname, tag)
        else
            local lhs, num = line:match("^local%s+([%w_]+)%s*=%s*([%d%.]+)")
            if lhs and num then
                local name_node = C.Name(lhs)
                local stmt = C.LocalAssign({ name_node }, { C.Number(num) })
                flush_item(stmt)
                local s = line:find(lhs, 1, true) or 1
                add_anchor(line0, s - 1, s - 1 + #lhs, name_node)
            else
                local a, b = line:match("^print%s*%(([%w_]+)%s*,%s*([%w_]+)%s*%)")
                if a and b then
                    local ra = C.NameRef(a)
                    local rb = C.NameRef(b)
                    local stmt = C.CallStmt(C.NameRef("print"), { ra, rb })
                    flush_item(stmt)
                    local s1 = line:find(a, 1, true) or 1
                    local s2 = line:find(b, s1 + #a, true) or (s1 + #a + 1)
                    add_anchor(line0, s1 - 1, s1 - 1 + #a, ra)
                    add_anchor(line0, s2 - 1, s2 - 1 + #b, rb)
                end
            end
        end
    end

    if #items == 0 then
        items[1] = C.Item({}, C.Break())
    end

    local file = C.File(uri, items)

    local pts = {}
    for i = 1, #positions do
        local p = positions[i]
        pts[i] = C.ServerAnchorPoint(
            C.AnchorRef(tostring(p.anchor)),
            C.LspRange(C.LspPos(p.line, p.start), C.LspPos(p.line, p["end"])),
            ""
        )
    end

    return file, C.ServerMeta(pts, "")
end

local function anchor_to_range(_file, anchor, _aid, meta)
    if not meta then return nil end
    local aid = anchor and anchor.id or ""
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

JsonRpc.run_stdio({
    parse = parse_toy,
    position_to_anchor = position_to_anchor,
    adapter_opts = { anchor_to_range = anchor_to_range },
})
