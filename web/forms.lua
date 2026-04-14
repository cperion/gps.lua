local M = {}

function M.bind(_T, H)
    local F = {}

    function F.csrf_hidden(token)
        return H.input({
            H.typ("hidden"),
            H.name("csrf_token"),
            H.value(token),
        })
    end

    function F.hidden(name, value)
        return H.input({
            H.typ("hidden"),
            H.name(name),
            H.value(value),
        })
    end

    function F.post(attrs, children, opts)
        opts = opts or {}
        local out = {}
        if opts.csrf_token ~= nil then
            out[#out + 1] = F.csrf_hidden(opts.csrf_token)
        end
        for i = 1, #(children or {}) do
            out[#out + 1] = children[i]
        end
        local a = {}
        for i = 1, #(attrs or {}) do
            a[i] = attrs[i]
        end
        a[#a + 1] = H.method("post")
        if opts.key ~= nil then
            return H.kel(opts.key, "form", a, out)
        end
        return H.form(a, out)
    end

    function F.live_post(action, attrs, children, opts)
        opts = opts or {}
        local a = {}
        for i = 1, #(attrs or {}) do
            a[i] = attrs[i]
        end
        a[#a + 1] = H.pvm_action(action)
        if opts.target_id ~= nil then
            a[#a + 1] = H.pvm_target(opts.target_id)
        end
        return F.post(a, children, opts)
    end

    function F.text_input(action, target_id, attrs, opts)
        opts = opts or {}
        local a = {}
        for i = 1, #(attrs or {}) do
            a[i] = attrs[i]
        end
        a[#a + 1] = H.pvm_event("input")
        a[#a + 1] = H.pvm_action(action)
        if target_id ~= nil then
            a[#a + 1] = H.pvm_target(target_id)
        end
        if opts.key ~= nil then
            return H.kel(opts.key, "input", a, {})
        end
        return H.input(a)
    end

    function F.live_text_input(key, action, target_id, attrs)
        return F.text_input(action, target_id, attrs, { key = key })
    end

    return F
end

return M
