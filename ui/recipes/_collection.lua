local b = require("ui.build")

local M = {}

local function key_string(key)
    return tostring(key)
end

function M.row_id(base_id, key)
    return b.id(base_id.value .. ":row:" .. key_string(key))
end

function M.slot_id(base_id, index)
    return b.id(base_id.value .. ":slot:" .. tostring(index))
end

function M.build(opts)
    opts = opts or {}

    local id = opts.id
    local items = opts.items or {}
    local key_of = opts.key_of
    local row = opts.row
    if id == nil then error("_collection.build requires opts.id", 2) end
    if key_of == nil then error("_collection.build requires opts.key_of", 2) end
    if row == nil then error("_collection.build requires opts.row", 2) end

    local selected_key = opts.selected_key
    local focused_key = opts.focused_key
    local dragged_key = opts.dragged_key
    local drop_index = opts.drop_index

    local row_infos = {}
    local slot_infos = {}
    local children = {}

    if opts.before_all ~= nil then
        local node = opts.before_all()
        if node ~= nil and node ~= false then
            children[#children + 1] = node
        end
    end

    if opts.build_slot ~= nil then
        local slot_id = M.slot_id(id, 1)
        local node = opts.build_slot(1, drop_index == 1, nil, nil, slot_id)
        if node ~= nil and node ~= false then
            children[#children + 1] = node
        end
        slot_infos[#slot_infos + 1] = {
            index = 1,
            id = slot_id,
        }
    end

    for i = 1, #items do
        local item = items[i]
        local key = key_of(item, i)
        local row_id = M.row_id(id, key)
        local before_slot_id = M.slot_id(id, i)
        local after_slot_id = M.slot_id(id, i + 1)

        local ctx = {
            index = i,
            key = key,
            first = i == 1,
            last = i == #items,
            selected = selected_key ~= nil and key == selected_key,
            focused = focused_key ~= nil and key == focused_key,
            dragged = dragged_key ~= nil and key == dragged_key,
            drop_before = drop_index == i,
            drop_after = drop_index == (i + 1),
            row_id = row_id,
            slot_before_id = before_slot_id,
            slot_after_id = after_slot_id,
        }

        row_infos[#row_infos + 1] = {
            key = key,
            item = item,
            index = i,
            id = row_id,
            ctx = ctx,
        }

        if opts.before_each ~= nil then
            local node = opts.before_each(i, item, ctx)
            if node ~= nil and node ~= false then
                children[#children + 1] = node
            end
        end

        local row_node = row(item, ctx)
        if opts.wrap_row ~= nil then
            row_node = opts.wrap_row(row_node, item, ctx)
        end
        if row_node ~= nil and row_node ~= false then
            children[#children + 1] = row_node
        end

        if opts.after_each ~= nil then
            local node = opts.after_each(i, item, ctx)
            if node ~= nil and node ~= false then
                children[#children + 1] = node
            end
        end

        if opts.build_slot ~= nil then
            local node = opts.build_slot(i + 1, drop_index == (i + 1), item, ctx, after_slot_id)
            if node ~= nil and node ~= false then
                children[#children + 1] = node
            end
            slot_infos[#slot_infos + 1] = {
                index = i + 1,
                id = after_slot_id,
            }
        end
    end

    if opts.after_all ~= nil then
        local node = opts.after_all()
        if node ~= nil and node ~= false then
            children[#children + 1] = node
        end
    end

    return {
        node = b.fragment(children),
        row_infos = row_infos,
        slot_infos = slot_infos,
    }
end

return M
