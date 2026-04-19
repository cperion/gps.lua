local types = require("watjit.types")
local struct = require("watjit.struct")
local union = require("watjit.union")

local function normalize_variants(variants)
    assert(type(variants) == "table", "tagged_union variants must be a table")
    local ordered = {}

    if #variants > 0 then
        for i = 1, #variants do
            local entry = variants[i]
            assert(type(entry) == "table", "tagged_union variant entries must be tables")
            local name = assert(entry[1], "tagged_union variant missing name")
            local t = assert(entry[2], "tagged_union variant missing type")
            assert(type(name) == "string", "tagged_union variant name must be a string")
            assert(type(t) == "table" and t.size, "tagged_union variant type must be a watjit type/layout")
            ordered[#ordered + 1] = { name = name, type = t }
        end
        return ordered
    end

    local names = {}
    for name in pairs(variants) do
        names[#names + 1] = name
    end
    table.sort(names)
    for i = 1, #names do
        local name = names[i]
        local t = variants[name]
        assert(type(name) == "string", "tagged_union variant name must be a string")
        assert(type(t) == "table" and t.size, "tagged_union variant type must be a watjit type/layout")
        ordered[#ordered + 1] = { name = name, type = t }
    end
    return ordered
end

local function tagged_union(name, spec)
    assert(type(name) == "string", "tagged_union name must be a string")
    assert(type(spec) == "table", "tagged_union spec must be a table")

    local ordered = normalize_variants(spec.variants or spec)
    assert(#ordered > 0, "tagged_union requires at least one variant")

    local tag_t = spec.tag_t or spec.tag_type or types.u8
    local tag_name = spec.tag_name or "tag"
    local payload_name = spec.payload_name or "payload"

    local tag_values = {}
    local payload_fields = {}
    local variants = {}

    for i = 1, #ordered do
        local variant = ordered[i]
        assert(tag_values[variant.name] == nil, "duplicate tagged_union variant: " .. variant.name)
        tag_values[variant.name] = i - 1
        payload_fields[#payload_fields + 1] = { variant.name, variant.type }
    end

    local payload_packed = spec.payload_packed
    if payload_packed == nil then
        payload_packed = false
    end
    local layout_packed = spec.packed
    if layout_packed == nil then
        layout_packed = false
    end

    local Tag = types.enum(name .. "_Tag", tag_t, tag_values)
    local Payload = union(name .. "_Payload", payload_fields, {
        packed = payload_packed,
        align = spec.payload_align,
    })

    local Layout = struct(name, {
        { tag_name, Tag },
        { payload_name, Payload },
    }, {
        packed = layout_packed,
        align = spec.align,
    })

    Layout.Tag = Tag
    Layout.Payload = Payload
    Layout.tag_field = tag_name
    Layout.payload_field = payload_name
    Layout.variants = variants
    Layout.variant_list = ordered

    for i = 1, #ordered do
        local variant = ordered[i]
        local info = {
            name = variant.name,
            type = variant.type,
            tag = Tag[variant.name],
            index = i - 1,
        }
        variants[variant.name] = info
        Layout[variant.name] = info.tag
    end

    return Layout
end

return tagged_union
