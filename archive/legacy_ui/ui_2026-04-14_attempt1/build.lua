local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Style = T.Style
local Auth = T.Auth

local M = {}

local NO_ID = Core.NoId
local EMPTY_STYLES = Style.TokenList({})
local EMPTY = Auth.Empty

local function classof(v)
    return pvm.classof(v)
end

local function is_id(v)
    local cls = classof(v)
    return cls and Core.Id.members[cls] or false
end

local function is_token(v)
    return classof(v) == Style.Token
end

local function is_group(v)
    return classof(v) == Style.Group
end

local function is_token_list(v)
    return classof(v) == Style.TokenList
end

local function is_node(v)
    local cls = classof(v)
    return cls and Auth.Node.members[cls] or false
end

local function append_style_value(v, styles)
    if is_token(v) then
        styles[#styles + 1] = v
        return true
    end

    if is_group(v) or is_token_list(v) then
        local items = v.items
        for i = 1, #items do
            styles[#styles + 1] = items[i]
        end
        return true
    end

    return false
end

local function text_leaf_from_scalar(v)
    return Auth.Text(NO_ID, EMPTY_STYLES, tostring(v))
end

local function classify_child(v, children)
    if v == nil or v == false then
        return
    end

    if type(v) == "string" or type(v) == "number" then
        children[#children + 1] = text_leaf_from_scalar(v)
        return
    end

    if is_node(v) then
        children[#children + 1] = v
        return
    end

    error("expected child node, string, number, nil, or false", 3)
end

local function finish_styles(styles)
    if #styles == 0 then
        return EMPTY_STYLES
    end
    return Style.TokenList(styles)
end

local function parse_box(items)
    local id = NO_ID
    local seen_id = false
    local styles = {}
    local children = {}

    for i = 1, #items do
        local v = items[i]
        if v ~= nil and v ~= false then
            if is_id(v) then
                if seen_id then
                    error("duplicate ui id in builder input", 3)
                end
                id = v
                seen_id = true
            elseif append_style_value(v, styles) then
                -- collected
            else
                classify_child(v, children)
            end
        end
    end

    return Auth.Box(id, finish_styles(styles), children)
end

local function parse_text(items)
    local id = NO_ID
    local seen_id = false
    local styles = {}
    local parts = {}

    for i = 1, #items do
        local v = items[i]
        if v ~= nil and v ~= false then
            if is_id(v) then
                if seen_id then
                    error("duplicate ui id in text builder input", 3)
                end
                id = v
                seen_id = true
            elseif append_style_value(v, styles) then
                -- collected
            elseif type(v) == "string" or type(v) == "number" then
                parts[#parts + 1] = tostring(v)
            else
                error("text builder accepts only id, style tokens/groups, strings, numbers, nil, or false", 3)
            end
        end
    end

    return Auth.Text(id, finish_styles(styles), table.concat(parts))
end

local function parse_fragment(items)
    local children = {}
    for i = 1, #items do
        classify_child(items[i], children)
    end
    return Auth.Fragment(children)
end

local function expect_table(items, level)
    if type(items) ~= "table" or classof(items) then
        error("builder expects one plain Lua array table", level or 3)
    end
    return items
end

function M.id(value)
    return Core.IdValue(value)
end

function M.box(items)
    return parse_box(expect_table(items, 2))
end

function M.text(items)
    return parse_text(expect_table(items, 2))
end

function M.fragment(items)
    return parse_fragment(expect_table(items, 2))
end

function M.each(items, fn)
    local children = {}
    for i = 1, #items do
        classify_child(fn(items[i], i), children)
    end
    return Auth.Fragment(children)
end

M.empty = EMPTY
M.T = T

return M
