local pvm = require("pvm")
local classof = pvm.classof

local M = {}

local function same_keys(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local function copy_path(path)
    local out = {}
    for i = 1, #path do
        out[i] = path[i]
    end
    return out
end

local function append_path(path, key)
    local out = copy_path(path)
    out[#out + 1] = key
    return out
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

    local Path = T.Patch.Path
    local Key = T.Patch.Key
    local Replace = T.Patch.Replace
    local Remove = T.Patch.Remove
    local Append = T.Patch.Append
    local SetAttr = T.Patch.SetAttr
    local RemoveAttr = T.Patch.RemoveAttr
    local SetText = T.Patch.SetText
    local Batch = T.Patch.Batch

    local function build_path(path)
        local segs = {}
        for i = 1, #path do
            segs[i] = Key(path[i])
        end
        return Path(segs)
    end

    local function emit_replace(ops, path, node)
        ops[#ops + 1] = Replace(build_path(path), node)
    end

    local function emit_remove(ops, path)
        ops[#ops + 1] = Remove(build_path(path))
    end

    local function emit_append(ops, path, node)
        ops[#ops + 1] = Append(build_path(path), node)
    end

    local function emit_set_attr(ops, path, name, value)
        ops[#ops + 1] = SetAttr(build_path(path), name, value)
    end

    local function emit_remove_attr(ops, path, name)
        ops[#ops + 1] = RemoveAttr(build_path(path), name)
    end

    local function emit_set_text(ops, path, text)
        ops[#ops + 1] = SetText(build_path(path), text)
    end

    local function keyed_child_key(node)
        if node == nil or node == HtmlEmpty then
            return nil
        end
        local mt = classof(node)
        if mt ~= mtEl then
            return nil
        end
        return node.key
    end

    local function normalize_root(node)
        if node ~= nil and classof(node) == mtDoc then
            return node.root, node.doctype
        end
        return node, nil
    end

    local function root_anchor_path(old_root, new_root)
        local old_mt = old_root and classof(old_root) or nil
        if old_mt == mtEl and old_root.key ~= nil then
            return { old_root.key }
        end
        local new_mt = new_root and classof(new_root) or nil
        if new_mt == mtEl and new_root.key ~= nil then
            return { new_root.key }
        end
        return {}
    end

    local function single_text_child(children)
        if #children ~= 1 then
            return nil
        end
        local child = children[1]
        if classof(child) == mtText then
            return child.content
        end
        return nil
    end

    local function attr_value(attr)
        local mt = classof(attr)
        if mt == mtAttrStr then
            return attr.value
        end
        if mt == mtAttrBool then
            return nil
        end
        return nil
    end

    local function diff_attrs(old_attrs, new_attrs, path, ops)
        if old_attrs == new_attrs then
            return true
        end

        local i, j = 1, 1
        while i <= #old_attrs or j <= #new_attrs do
            local oa = old_attrs[i]
            local na = new_attrs[j]

            if oa == nil then
                emit_set_attr(ops, path, na.name, attr_value(na))
                j = j + 1
            elseif na == nil then
                emit_remove_attr(ops, path, oa.name)
                i = i + 1
            elseif oa.name == na.name then
                local ov = attr_value(oa)
                local nv = attr_value(na)
                if classof(oa) ~= classof(na) or ov ~= nv then
                    emit_set_attr(ops, path, na.name, nv)
                end
                i = i + 1
                j = j + 1
            elseif oa.name < na.name then
                emit_remove_attr(ops, path, oa.name)
                i = i + 1
            else
                emit_set_attr(ops, path, na.name, attr_value(na))
                j = j + 1
            end
        end

        return true
    end

    local diff_node

    local function diff_keyed_children(old_children, new_children, parent_path, ops)
        local old_by_key, new_by_key = {}, {}
        local old_keys, new_keys = {}, {}

        for i = 1, #old_children do
            local child = old_children[i]
            if child ~= HtmlEmpty then
                local key = keyed_child_key(child)
                if key == nil or old_by_key[key] ~= nil then
                    return false
                end
                old_by_key[key] = child
                old_keys[#old_keys + 1] = key
            end
        end

        for i = 1, #new_children do
            local child = new_children[i]
            if child ~= HtmlEmpty then
                local key = keyed_child_key(child)
                if key == nil or new_by_key[key] ~= nil then
                    return false
                end
                new_by_key[key] = child
                new_keys[#new_keys + 1] = key
            end
        end

        local old_keep, new_keep = {}, {}
        for i = 1, #old_keys do
            local key = old_keys[i]
            if new_by_key[key] ~= nil then
                old_keep[#old_keep + 1] = key
            end
        end
        for i = 1, #new_keys do
            local key = new_keys[i]
            if old_by_key[key] ~= nil then
                new_keep[#new_keep + 1] = key
            end
        end

        if not same_keys(old_keep, new_keep) then
            return false
        end

        local seen_new_only = false
        for i = 1, #new_keys do
            local key = new_keys[i]
            if old_by_key[key] ~= nil then
                if seen_new_only then
                    return false
                end
            else
                seen_new_only = true
            end
        end

        for i = 1, #old_keep do
            local key = old_keep[i]
            if not diff_node(old_by_key[key], new_by_key[key], append_path(parent_path, key), ops, true) then
                return false
            end
        end

        for i = 1, #old_keys do
            local key = old_keys[i]
            if new_by_key[key] == nil then
                emit_remove(ops, append_path(parent_path, key))
            end
        end

        local appending = false
        for i = 1, #new_keys do
            local key = new_keys[i]
            local child = new_by_key[key]
            if old_by_key[key] == nil then
                appending = true
                emit_append(ops, parent_path, child)
            elseif appending then
                return false
            end
        end

        return true
    end

    local function diff_children(old_children, new_children, parent_path, ops)
        if old_children == new_children then
            return true
        end

        if diff_keyed_children(old_children, new_children, parent_path, ops) then
            return true
        end

        local old_n = #old_children
        local new_n = #new_children
        local min_n = old_n < new_n and old_n or new_n

        for i = 1, min_n do
            local old_child = old_children[i]
            local new_child = new_children[i]
            if old_child ~= new_child then
                local old_key = keyed_child_key(old_child)
                local new_key = keyed_child_key(new_child)
                if old_key ~= nil and new_key ~= nil and old_key == new_key then
                    if not diff_node(old_child, new_child, append_path(parent_path, new_key), ops, true) then
                        return false
                    end
                else
                    return false
                end
            end
        end

        if old_n > new_n then
            for i = new_n + 1, old_n do
                local key = keyed_child_key(old_children[i])
                if key == nil then
                    return false
                end
                emit_remove(ops, append_path(parent_path, key))
            end
            return true
        end

        if new_n > old_n then
            for i = old_n + 1, new_n do
                local child = new_children[i]
                local key = keyed_child_key(child)
                if key == nil then
                    return false
                end
                emit_append(ops, parent_path, child)
            end
            return true
        end

        return true
    end

    diff_node = function(old, new, path, ops, targetable)
        if old == new then
            return true
        end

        if old == nil then
            if targetable then
                emit_replace(ops, path, new)
                return true
            end
            return false
        end

        if new == nil then
            if targetable then
                emit_remove(ops, path)
                return true
            end
            return false
        end

        local mt_old = classof(old)
        local mt_new = classof(new)

        if mt_old ~= mt_new then
            if targetable then
                emit_replace(ops, path, new)
                return true
            end
            return false
        end

        if mt_new == mtEl then
            if old.tag ~= new.tag or old.key ~= new.key then
                if targetable then
                    emit_replace(ops, path, new)
                    return true
                end
                return false
            end

            local old_text = single_text_child(old.children)
            local new_text = single_text_child(new.children)
            if old_text ~= nil and new_text ~= nil then
                diff_attrs(old.attrs, new.attrs, path, ops)
                if old_text ~= new_text then
                    emit_set_text(ops, path, new_text)
                end
                return true
            end

            diff_attrs(old.attrs, new.attrs, path, ops)
            if diff_children(old.children, new.children, path, ops) then
                return true
            end
            if targetable then
                emit_replace(ops, path, new)
                return true
            end
            return false
        end

        if mt_new == mtFragment then
            if diff_children(old.children, new.children, path, ops) then
                return true
            end
            if targetable then
                emit_replace(ops, path, new)
                return true
            end
            return false
        end

        if mt_new == mtText then
            if old.content == new.content then
                return true
            end
            if targetable then
                emit_set_text(ops, path, new.content)
                return true
            end
            return false
        end

        if mt_new == mtRaw then
            if old.html == new.html then
                return true
            end
            if targetable then
                emit_replace(ops, path, new)
                return true
            end
            return false
        end

        if mt_new == mtDoc then
            if old.doctype ~= new.doctype then
                if targetable then
                    emit_replace(ops, path, new.root)
                    return true
                end
                return false
            end
            return diff_node(old.root, new.root, path, ops, targetable)
        end

        if old == new then
            return true
        end

        if targetable then
            emit_replace(ops, path, new)
            return true
        end
        return false
    end

    local API = {}

    function API.diff(old, new)
        local ops = {}
        local old_root = normalize_root(old)
        local new_root = normalize_root(new)
        local path = root_anchor_path(old_root, new_root)
        diff_node(old_root, new_root, path, ops, true)
        return Batch(ops)
    end

    return API
end

return M
