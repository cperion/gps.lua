local stream = require("web.stream")

local M = {}

local function nop() end

function M.split_url(url)
    local path, query = tostring(url or "/"):match("^([^?]*)%??(.*)$")
    return path or "/", query ~= "" and query or nil
end

function M.percent_decode(s)
    s = tostring(s or "")
    s = s:gsub("+", " ")
    s = s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return s
end

function M.parse_query_string(qs)
    local out = {}
    if not qs then
        return out
    end
    for key, value in qs:gmatch("([^&=?]+)=([^&=?]*)") do
        out[M.percent_decode(key)] = M.percent_decode(value)
    end
    return out
end

function M.headers_to_table(headers)
    local out = {}
    if headers == nil then
        return out
    end
    for i = 1, #headers do
        out[headers[i].name] = headers[i].value
    end
    return out
end

function M.make_request(req)
    local path, qs = M.split_url(req.url)
    return {
        method = req.method or "GET",
        url = req.url or path,
        path = path,
        query = M.parse_query_string(qs),
        headers = req.headers,
    }
end

function M.write_head(res, status, headers)
    local header_table = headers
    if type(headers) ~= "table" or (#headers > 0 and headers[1] ~= nil) then
        header_table = M.headers_to_table(headers)
    end

    if res.writeHead then
        res:writeHead(status, header_table)
        return
    end

    if res.statusCode ~= nil then
        res.statusCode = status
    end

    if res.setHeader then
        for name, value in pairs(header_table) do
            res:setHeader(name, value)
        end
    end
end

function M.send(res, status, headers, g, p, c, on_done, on_error)
    on_done = on_done or nop
    on_error = on_error or nop
    M.write_head(res, status, headers)
    return stream.luvit(res, g, p, c, on_done, on_error)
end

function M.send_html(res, status, headers, render, html, on_done, on_error)
    local g, p, c = render(html)
    return M.send(res, status, headers, g, p, c, on_done, on_error)
end

function M.handler(opts)
    local make_request = opts.make_request or M.make_request
    local build = assert(opts.build, "web.http.handler: missing build(req, raw_req, res)")
    local render = assert(opts.render, "web.http.handler: missing render phase")
    local on_error = opts.on_error or function(err, _req, res)
        M.write_head(res, 500, { ["Content-Type"] = "text/plain; charset=utf-8" })
        res:finish("internal error\n" .. tostring(err))
    end

    return function(req, res)
        local web_req = make_request(req)
        local ok, status, headers, html = xpcall(function()
            return build(web_req, req, res)
        end, debug.traceback)

        if not ok then
            return on_error(status, web_req, res)
        end

        return M.send_html(res, status, headers, render, html, function()
            res:finish()
        end, function(err)
            on_error(err, web_req, res)
        end)
    end
end

function M.serve(opts)
    local http_mod = opts.http or require("http")
    local server = http_mod.createServer(M.handler(opts))
    server:listen(opts.port or 8080, opts.host or "0.0.0.0")
    return server
end

return M
