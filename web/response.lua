local pvm = require("pvm")

local M = {}

local function resolve_module(T, mod)
    if type(mod) == "string" then
        local m = T[mod]
        if not m then
            error("web.response.bind: unknown module '" .. mod .. "'", 2)
        end
        return m
    end
    return mod
end

local function has_header(headers, name)
    for i = 1, #headers do
        if headers[i].name:lower() == name then
            return true
        end
    end
    return false
end

function M.bind(T, mod)
    local W = resolve_module(T, mod)
    assert(W and W.Header and W.Response and W.PageBody and W.HtmlBody,
        "web.response.bind: module must provide Header, Response, PageBody, HtmlBody")

    local API = {}

    function API.header(name, value)
        return W.Header(tostring(name), tostring(value))
    end

    function API.headers(spec)
        if spec == nil then
            return {}
        end
        if #spec > 0 then
            return spec
        end
        local out = {}
        for name, value in pairs(spec) do
            out[#out + 1] = W.Header(tostring(name), tostring(value))
        end
        table.sort(out, function(a, b)
            return a.name < b.name
        end)
        return out
    end

    function API.with_default_html_headers(headers)
        headers = API.headers(headers)
        if not has_header(headers, "content-type") then
            local out = {}
            for i = 1, #headers do
                out[i] = headers[i]
            end
            out[#out + 1] = W.Header("Content-Type", "text/html; charset=utf-8")
            table.sort(out, function(a, b)
                return a.name < b.name
            end)
            return out
        end
        return headers
    end

    function API.page(status, headers, view)
        return W.Response(status, API.with_default_html_headers(headers), W.PageBody(view))
    end

    function API.html(status, headers, node)
        return W.Response(status, API.with_default_html_headers(headers), W.HtmlBody(node))
    end

    function API.ok_page(view, headers)
        return API.page(200, headers, view)
    end

    function API.ok_html(node, headers)
        return API.html(200, headers, node)
    end

    function API.not_found_page(view, headers)
        return API.page(404, headers, view)
    end

    function API.body_to_html(template, body)
        if body.kind == "PageBody" then
            return pvm.one(template(body.view))
        end
        return body.node
    end

    function API.compile(template, response)
        return API.body_to_html(template, response.body)
    end

    return API
end

return M
