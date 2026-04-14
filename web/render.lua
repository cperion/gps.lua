local pvm = require("pvm")
local classof = pvm.classof
local escape = require("web.escape")

local M = {}

local table_concat = table.concat

local VOID_TAGS = {
    area = true,
    base = true,
    br = true,
    col = true,
    embed = true,
    hr = true,
    img = true,
    input = true,
    link = true,
    meta = true,
    param = true,
    source = true,
    track = true,
    wbr = true,
}

local function fold_string(g, p, c)
    local out, n = {}, 0
    while true do
        local v
        c, v = g(p, c)
        if c == nil then
            break
        end
        n = n + 1
        out[n] = v
    end
    return table_concat(out)
end

function M.bind(T)
    local HtmlEmpty = T.Html.Empty

    local mtDoc = classof(T.Html.Doc("html", HtmlEmpty))
    local mtEl = classof(T.Html.El("div", nil, {}, {}))
    local mtText = classof(T.Html.Text(""))
    local mtRaw = classof(T.Html.Raw(""))
    local mtFragment = classof(T.Html.Fragment({}))
    local mtAttrStr = classof(T.Html.Str("", ""))
    local mtAttrBool = classof(T.Html.Bool(""))

    local function render_attrs(attrs, live_key)
        local out, n = {}, 0
        local has_live_key = false

        for i = 1, #attrs do
            local attr = attrs[i]
            local mt = classof(attr)
            if mt == mtAttrStr then
                local name = attr.name
                if name == "data-pvm-key" then
                    has_live_key = true
                end
                n = n + 1
                out[n] = " " .. name .. '="' .. escape.attr(attr.value) .. '"'
            elseif mt == mtAttrBool then
                local name = attr.name
                if name == "data-pvm-key" then
                    has_live_key = true
                end
                n = n + 1
                out[n] = " " .. name
            else
                error("web.render: expected Html.Attr")
            end
        end

        if live_key ~= nil and not has_live_key then
            n = n + 1
            out[n] = ' data-pvm-key="' .. escape.attr(live_key) .. '"'
        end

        if n == 0 then
            return ""
        end
        return table_concat(out)
    end

    local function make_render_phase(name, live)
        local render
        render = pvm.phase(name, {
            [T.Html.Doc] = function(self)
                local prefix = "<!doctype " .. self.doctype .. ">"
                local g1, p1, c1 = pvm.once(prefix)
                local g2, p2, c2 = render(self.root)
                return pvm.concat2(g1, p1, c1, g2, p2, c2)
            end,

            [T.Html.El] = function(self)
                local attrs = render_attrs(self.attrs, live and self.key or nil)
                local open = "<" .. self.tag .. attrs .. ">"

                if VOID_TAGS[self.tag] then
                    return pvm.once(open)
                end

                if #self.children == 0 then
                    return pvm.once(open .. "</" .. self.tag .. ">")
                end

                local g1, p1, c1 = pvm.once(open)
                local g2, p2, c2 = pvm.children(render, self.children)
                local g3, p3, c3 = pvm.once("</" .. self.tag .. ">")
                return pvm.concat3(g1, p1, c1, g2, p2, c2, g3, p3, c3)
            end,

            [T.Html.Text] = function(self)
                return pvm.once(escape.text(self.content))
            end,

            [T.Html.Raw] = function(self)
                return pvm.once(self.html)
            end,

            [T.Html.Fragment] = function(self)
                return pvm.children(render, self.children)
            end,

            [T.Html.Empty] = function(_)
                return pvm.empty()
            end,
        })
        return render
    end

    local render = make_render_phase("web.render", false)
    local render_live = make_render_phase("web.render_live", true)

    return {
        render = render,
        render_live = render_live,

        to_string = function(node)
            return fold_string(render(node))
        end,

        to_string_live = function(node)
            return fold_string(render_live(node))
        end,

        mt = {
            Doc = mtDoc,
            El = mtEl,
            Text = mtText,
            Raw = mtRaw,
            Fragment = mtFragment,
        },
    }
end

return M
