local pvm = require("pvm")
local classof = pvm.classof

local M = {}

local table_sort = table.sort

local function copy_compact(t)
    if t == nil then
        return {}
    end
    local out, n = {}, 0
    for i = 1, #t do
        local v = t[i]
        if v ~= nil then
            n = n + 1
            out[n] = v
        end
    end
    return out
end

function M.bind(T)
    local H = {}

    local Empty = T.Html.Empty
    local El = T.Html.El
    local Doc = T.Html.Doc
    local Text = T.Html.Text
    local Raw = T.Html.Raw
    local Fragment = T.Html.Fragment

    local AttrStr = T.Html.Str
    local AttrBool = T.Html.Bool

    local mtDoc = classof(Doc("html", Empty))
    local mtEl = classof(El("div", nil, {}, {}))
    local mtText = classof(Text(""))
    local mtRaw = classof(Raw(""))
    local mtFragment = classof(Fragment({}))
    local mtAttrStr = classof(AttrStr("", ""))
    local mtAttrBool = classof(AttrBool(""))

    local function is_html_node(node)
        if node == Empty then
            return true
        end
        local mt = classof(node)
        return mt == mtDoc
            or mt == mtEl
            or mt == mtText
            or mt == mtRaw
            or mt == mtFragment
    end

    local function normalize_attrs(attrs)
        if attrs == nil then
            return {}
        end
        local out, n = {}, 0
        local seen = {}
        for i = 1, #attrs do
            local attr = attrs[i]
            if attr ~= nil then
                local mt = classof(attr)
                if mt ~= mtAttrStr and mt ~= mtAttrBool then
                    error("web.html: expected Html.Attr", 3)
                end
                local name = attr.name
                if seen[name] then
                    error("web.html: duplicate attribute '" .. name .. "'", 3)
                end
                seen[name] = true
                n = n + 1
                out[n] = attr
            end
        end
        table_sort(out, function(a, b)
            return a.name < b.name
        end)
        return out
    end

    local function append_child(out, n, child)
        if child == nil or child == Empty then
            return n
        end
        if not is_html_node(child) then
            error("web.html: expected Html.Node", 3)
        end
        if classof(child) == mtFragment then
            for j = 1, #child.children do
                n = append_child(out, n, child.children[j])
            end
            return n
        end
        n = n + 1
        out[n] = child
        return n
    end

    local function normalize_children(children)
        if children == nil then
            return {}
        end
        local out, n = {}, 0
        for i = 1, #children do
            n = append_child(out, n, children[i])
        end
        return out
    end

    function H.doc(root)
        return Doc("html", root or Empty)
    end

    function H.doc_type(doctype, root)
        return Doc(tostring(doctype or "html"), root or Empty)
    end

    function H.el(tag, attrs, children)
        return El(tostring(tag), nil, normalize_attrs(attrs), normalize_children(children))
    end

    function H.kel(key, tag, attrs, children)
        if key == nil then
            error("web.html.kel: key must not be nil", 2)
        end
        return El(tostring(tag), tostring(key), normalize_attrs(attrs), normalize_children(children))
    end

    function H.text(x)
        return Text(tostring(x or ""))
    end

    function H.raw(html)
        return Raw(tostring(html or ""))
    end

    function H.frag(children)
        local normalized = normalize_children(children)
        if #normalized == 0 then
            return Empty
        end
        return Fragment(normalized)
    end

    H.empty = Empty

    function H.attr(name, value)
        return AttrStr(tostring(name), tostring(value or ""))
    end

    function H.bool(name, on)
        if not on then
            return nil
        end
        return AttrBool(tostring(name))
    end

    function H.data(name, value)
        return AttrStr("data-" .. tostring(name), tostring(value or ""))
    end

    function H.cls(name)
        return AttrStr("class", tostring(name or ""))
    end

    function H.id(name)
        return AttrStr("id", tostring(name or ""))
    end

    function H.href(url)
        return AttrStr("href", tostring(url or ""))
    end

    function H.src(url)
        return AttrStr("src", tostring(url or ""))
    end

    function H.rel(value)
        return AttrStr("rel", tostring(value or ""))
    end

    function H.name(value)
        return AttrStr("name", tostring(value or ""))
    end

    function H.value(value)
        return AttrStr("value", tostring(value or ""))
    end

    function H.method(value)
        return AttrStr("method", tostring(value or ""))
    end

    function H.typ(value)
        return AttrStr("type", tostring(value or ""))
    end

    function H.pvm_action(action)
        return AttrStr("data-pvm-action", tostring(action or ""))
    end

    function H.pvm_target(target_id)
        return AttrStr("data-target-id", tostring(target_id or ""))
    end

    function H.pvm_event(kind)
        return AttrStr("data-pvm-event", tostring(kind or ""))
    end

    function H.when(cond, node)
        if cond then
            return node or Empty
        end
        return Empty
    end

    function H.maybe(value, fn)
        if value == nil then
            return Empty
        end
        local node = fn(value)
        return node or Empty
    end

    function H.each(items, fn)
        if items == nil then
            return Empty
        end
        local out, n = {}, 0
        for i = 1, #items do
            local node = fn(items[i], i)
            if node ~= nil and node ~= Empty then
                if not is_html_node(node) then
                    error("web.html.each: callback must return Html.Node", 2)
                end
                n = n + 1
                out[n] = node
            end
        end
        if n == 0 then
            return Empty
        end
        return Fragment(out)
    end

    local function make_tag(tag, void)
        if void then
            return function(attrs)
                return El(tag, nil, normalize_attrs(attrs), {})
            end
        end
        return function(attrs, children)
            return El(tag, nil, normalize_attrs(attrs), normalize_children(children))
        end
    end

    H.html = make_tag("html")
    H.head = make_tag("head")
    H.body = make_tag("body")
    H.title = make_tag("title")
    H.meta = make_tag("meta", true)
    H.link = make_tag("link", true)
    H.script = make_tag("script")

    H.main = make_tag("main")
    H.header = make_tag("header")
    H.footer = make_tag("footer")
    H.nav = make_tag("nav")
    H.section = make_tag("section")
    H.article = make_tag("article")
    H.div = make_tag("div")
    H.span = make_tag("span")
    H.p = make_tag("p")
    H.a = make_tag("a")

    H.h1 = make_tag("h1")
    H.h2 = make_tag("h2")
    H.h3 = make_tag("h3")
    H.ul = make_tag("ul")
    H.ol = make_tag("ol")
    H.li = make_tag("li")

    H.img = make_tag("img", true)
    H.form = make_tag("form")
    H.input = make_tag("input", true)
    H.button = make_tag("button")
    H.label = make_tag("label")
    H.textarea = make_tag("textarea")

    H.compact = copy_compact

    return H
end

return M
