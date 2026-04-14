local M = {}

local client_js_cache = nil

local function load_client_js(path)
    if client_js_cache ~= nil and path == nil then
        return client_js_cache
    end
    local f = assert(io.open(path or "web/client.js", "rb"))
    local s = assert(f:read("*a"))
    f:close()
    if path == nil then
        client_js_cache = s
    end
    return s
end

function M.bind(H, ws_port, opts)
    opts = opts or {}

    local client_js = opts.client_js or load_client_js(opts.client_js_path)
    local client_js_src = opts.client_js_src
    local bootstrap_js_src = opts.bootstrap_js_src
    local root_key = opts.root_key or "root"
    local body_key = opts.body_key or "page"
    local charset = opts.charset or "utf-8"

    local function bootstrap_script(path_expr)
        path_expr = path_expr or "location.pathname"
        return [[
(function () {
  function connect() {
    if (!window.PVMWeb) return
    var proto = location.protocol === "https:" ? "wss://" : "ws://"
    var url = proto + location.hostname + ":]] .. tostring(ws_port) .. [[/?path=" + encodeURIComponent(]] .. path_expr .. [[)
    PVMWeb.connect({ url: url })
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", connect)
  } else {
    connect()
  }
})()
]]
    end

    local function script_nodes(path_expr)
        local client_node
        if client_js_src ~= nil then
            client_node = H.kel("client-js", "script", { H.src(client_js_src) }, {})
        else
            client_node = H.kel("client-js", "script", {}, { H.raw(client_js) })
        end

        local bootstrap_node
        if bootstrap_js_src ~= nil then
            bootstrap_node = H.kel("bootstrap-js", "script", { H.src(bootstrap_js_src) }, {})
        else
            bootstrap_node = H.kel("bootstrap-js", "script", {}, { H.raw(bootstrap_script(path_expr)) })
        end

        return {
            client_node,
            bootstrap_node,
        }
    end

    local function shell(title, body_children, shell_opts)
        shell_opts = shell_opts or {}
        local head_children = {
            H.kel("page-title", "title", {}, { H.text(title) }),
            H.kel("charset-meta", "meta", { H.attr("charset", charset) }, {}),
        }
        local extra_head = shell_opts.head_children or {}
        for i = 1, #extra_head do
            head_children[#head_children + 1] = extra_head[i]
        end

        local body_out = {}
        for i = 1, #(body_children or {}) do
            body_out[#body_out + 1] = body_children[i]
        end
        local scripts = script_nodes(shell_opts.path_expr)
        for i = 1, #scripts do
            body_out[#body_out + 1] = scripts[i]
        end

        return H.doc(H.kel(root_key, "html", shell_opts.html_attrs or {}, {
            H.kel("head", "head", shell_opts.head_attrs or {}, head_children),
            H.kel(body_key, "body", shell_opts.body_attrs or {}, body_out),
        }))
    end

    return {
        client_js = client_js,
        bootstrap_script = bootstrap_script,
        script_nodes = script_nodes,
        shell = shell,
    }
end

return M
