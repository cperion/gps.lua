local pvm = require("pvm")
local classof = pvm.classof

local M = {}

local table_concat = table.concat

local function json_quote(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\b", "\\b")
    s = s:gsub("\f", "\\f")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return '"' .. s .. '"'
end

function M.bind(T, render_live_or_bundle)
    local render_live = render_live_or_bundle.render_live or render_live_or_bundle

    local mtReplace = classof(T.Patch.Replace(T.Patch.Path({}), T.Html.Empty))
    local mtRemove = classof(T.Patch.Remove(T.Patch.Path({})))
    local mtAppend = classof(T.Patch.Append(T.Patch.Path({}), T.Html.Empty))
    local mtSetAttr = classof(T.Patch.SetAttr(T.Patch.Path({}), "", nil))
    local mtRemoveAttr = classof(T.Patch.RemoveAttr(T.Patch.Path({}), ""))
    local mtSetText = classof(T.Patch.SetText(T.Patch.Path({}), ""))

    local function render_node(node)
        local chunks = pvm.drain(render_live(node))
        return table_concat(chunks)
    end

    local function encode_path(path)
        local out, n = {"["}, 1
        for i = 1, #path.segs do
            if i > 1 then
                n = n + 1
                out[n] = ","
            end
            n = n + 1
            out[n] = json_quote(path.segs[i].key)
        end
        n = n + 1
        out[n] = "]"
        return table_concat(out)
    end

    local function encode_op(op)
        local mt = classof(op)
        if mt == mtReplace then
            return "{" ..
                '"op":"replace","path":' .. encode_path(op.path) ..
                ',"html":' .. json_quote(render_node(op.node)) ..
                "}"
        end
        if mt == mtRemove then
            return "{" ..
                '"op":"remove","path":' .. encode_path(op.path) ..
                "}"
        end
        if mt == mtAppend then
            return "{" ..
                '"op":"append","path":' .. encode_path(op.path) ..
                ',"html":' .. json_quote(render_node(op.node)) ..
                "}"
        end
        if mt == mtSetAttr then
            local s = "{" ..
                '"op":"set_attr","path":' .. encode_path(op.path) ..
                ',"name":' .. json_quote(op.name)
            if op.value ~= nil then
                s = s .. ',"value":' .. json_quote(op.value)
            end
            return s .. "}"
        end
        if mt == mtRemoveAttr then
            return "{" ..
                '"op":"remove_attr","path":' .. encode_path(op.path) ..
                ',"name":' .. json_quote(op.name) ..
                "}"
        end
        if mt == mtSetText then
            return "{" ..
                '"op":"set_text","path":' .. encode_path(op.path) ..
                ',"text":' .. json_quote(op.text) ..
                "}"
        end
        error("web.encode: unsupported Patch.Op")
    end

    local API = {}

    function API.batch(batch)
        local out, n = {"["}, 1
        for i = 1, #batch.ops do
            if i > 1 then
                n = n + 1
                out[n] = ","
            end
            n = n + 1
            out[n] = encode_op(batch.ops[i])
        end
        n = n + 1
        out[n] = "]"
        return table_concat(out)
    end

    function API.path(path)
        return encode_path(path)
    end

    return API
end

return M
