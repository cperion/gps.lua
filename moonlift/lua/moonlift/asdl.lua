return function(ctx)
    local parse = assert(ctx.parse, "moonlift.asdl requires parse api")
    local caller_env = assert(ctx.caller_env, "moonlift.asdl requires caller_env")

    local type = type
    local error = error
    local assert = assert
    local tonumber = tonumber
    local tostring = tostring
    local ipairs = ipairs
    local pairs = pairs
    local rawget = rawget
    local rawset = rawset
    local setmetatable = setmetatable
    local getmetatable = getmetatable
    local tconcat = table.concat
    local math_floor = math.floor
    local math_huge = math.huge

    local RESERVED_TOPLEVEL = {
        with = true,
        classof = true,
        is = true,
    }

    local SCALAR_ALIASES = {
        byte = "u8",
        isize = "i64",
        usize = "u64",
    }

    local SCALAR_TYPES = {
        bool = true,
        i8 = true,
        i16 = true,
        i32 = true,
        i64 = true,
        u8 = true,
        u16 = true,
        u32 = true,
        u64 = true,
        f32 = true,
        f64 = true,
    }

    local INTEGER_SCALARS = {
        i8 = true,
        i16 = true,
        i32 = true,
        i64 = true,
        u8 = true,
        u16 = true,
        u32 = true,
        u64 = true,
    }

    local UNSIGNED_SCALARS = {
        u8 = true,
        u16 = true,
        u32 = true,
        u64 = true,
    }

    local function is_plain_table(v)
        return type(v) == "table" and getmetatable(v) == nil
    end

    local function join_path(path)
        return tconcat(path.segments or {}, ".")
    end

    local function normalize_scalar_name(name)
        return SCALAR_ALIASES[name] or name
    end

    local function is_identifier_reserved(name)
        return type(name) == "string" and name:sub(1, 2) == "__"
    end

    local function quote_string(s)
        return string.format("%q", s)
    end

    local function serialize_number(n)
        if n ~= n then return "nan" end
        if n == math_huge then return "inf" end
        if n == -math_huge then return "-inf" end
        if n == 0 and 1 / n < 0 then return "-0" end
        return string.format("%.17g", n)
    end

    local function serialize_atom(v)
        local tv = type(v)
        if tv == "string" then
            return "s:" .. quote_string(v)
        elseif tv == "number" then
            return "n:" .. serialize_number(v)
        elseif tv == "boolean" then
            return v and "b:1" or "b:0"
        elseif v == nil then
            return "nil"
        end
        error("moonlift.asdl cannot serialize value of type '" .. tv .. "'", 2)
    end

    local function pretty_atom(v)
        local tv = type(v)
        if tv == "string" then
            return quote_string(v)
        elseif tv == "number" then
            return serialize_number(v)
        elseif tv == "boolean" then
            return tostring(v)
        elseif v == nil then
            return "nil"
        end
        return tostring(v)
    end

    local function is_integral_number(v)
        return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge and math_floor(v) == v
    end

    local function choose_unsigned_type(n)
        if n <= 0xff then return "u8" end
        if n <= 0xffff then return "u16" end
        if n <= 0xffffffff then return "u32" end
        return "u64"
    end

    local function eval_const_integer(expr, where)
        local tag = expr and expr.tag
        if tag == "number" then
            assert(expr.kind == "int", ("moonlift.asdl %s expects an integer literal"):format(where))
            local v = tonumber(expr.raw)
            assert(v ~= nil and is_integral_number(v), ("moonlift.asdl %s expects an integer literal"):format(where))
            return v
        elseif tag == "unary" and expr.op == "neg" then
            return -eval_const_integer(expr.expr, where)
        end
        error(("moonlift.asdl %s expects an integer constant"):format(where), 2)
    end

    local function normalize_type_ast(ast, where)
        local tag = ast and ast.tag
        if tag == "path" then
            local name = join_path(ast)
            local scalar = normalize_scalar_name(name)
            if SCALAR_TYPES[scalar] then
                return { tag = "scalar", name = scalar }
            elseif name == "string" then
                return { tag = "string" }
            elseif name == "bytes" then
                return { tag = "bytes" }
            end
            return { tag = "ref", name = name }
        elseif tag == "slice" then
            return { tag = "seq", elem = normalize_type_ast(ast.elem, where) }
        elseif tag == "array" then
            return {
                tag = "array",
                len = eval_const_integer(ast.len, where .. " array length"),
                elem = normalize_type_ast(ast.elem, where),
            }
        elseif tag == nil and ast ~= nil then
            error(("moonlift.asdl %s uses an unsupported type form"):format(where), 2)
        elseif tag == "group" then
            return normalize_type_ast(ast.inner, where)
        elseif tag == "pointer" or tag == "func_type" or tag == "splice" then
            error(("moonlift.asdl %s uses unsupported type syntax '%s'"):format(where, tag), 2)
        end
        error(("moonlift.asdl %s uses an unsupported type form '%s'"):format(where, tostring(tag)), 2)
    end

    local function normalize_tag_base(ast, where)
        if ast == nil then return nil end
        local ty = normalize_type_ast(ast, where)
        assert(ty.tag == "scalar" and UNSIGNED_SCALARS[ty.name],
            ("moonlift.asdl %s base type must be one of u8/u16/u32/u64"):format(where))
        return ty.name
    end

    local function attr_unique(attrs, where)
        local unique = false
        for i = 1, #(attrs or {}) do
            local attr = attrs[i]
            if attr.name == "unique" then
                assert(not unique, ("moonlift.asdl %s repeats @unique"):format(where))
                assert(#(attr.args or {}) == 0, ("moonlift.asdl %s @unique takes no arguments"):format(where))
                unique = true
            else
                error(("moonlift.asdl %s does not support @%s"):format(where, tostring(attr.name)), 2)
            end
        end
        return unique
    end

    local function check_name(name, where)
        assert(type(name) == "string" and name ~= "", ("moonlift.asdl %s is missing a name"):format(where))
        assert(not is_identifier_reserved(name), ("moonlift.asdl %s name '%s' is reserved"):format(where, name))
        return name
    end

    local function lower_fields(fields, owner)
        local out = {}
        local seen = {}
        for i = 1, #(fields or {}) do
            local field = fields[i]
            local name = check_name(field.name, owner .. " field")
            assert(not seen[name], ("moonlift.asdl %s repeats field '%s'"):format(owner, name))
            seen[name] = true
            out[#out + 1] = {
                name = name,
                type = normalize_type_ast(field.ty, owner .. "." .. name),
            }
        end
        return out
    end

    local function lower_module_ast(module_ast)
        assert(type(module_ast) == "table" and module_ast.tag == "module", "moonlift.asdl expects a parsed module AST")
        local decls = {}
        local by_name = {}

        for i = 1, #(module_ast.items or {}) do
            local item = module_ast.items[i]
            local tag = item.tag
            local decl

            if tag == "type_alias" then
                local name = check_name(item.name, "type alias")
                assert(not RESERVED_TOPLEVEL[name], ("moonlift.asdl top-level name '%s' is reserved"):format(name))
                decl = {
                    tag = "alias",
                    name = name,
                    ty = normalize_type_ast(item.ty, "type alias '" .. name .. "'"),
                }
            elseif tag == "struct" then
                local name = check_name(item.name, "struct")
                assert(not RESERVED_TOPLEVEL[name], ("moonlift.asdl top-level name '%s' is reserved"):format(name))
                decl = {
                    tag = "struct",
                    name = name,
                    unique = attr_unique(item.attrs, "struct '" .. name .. "'"),
                    fields = lower_fields(item.fields, "struct '" .. name .. "'"),
                }
            elseif tag == "tagged_union" then
                local name = check_name(item.name, "tagged union")
                assert(not RESERVED_TOPLEVEL[name], ("moonlift.asdl top-level name '%s' is reserved"):format(name))
                local variants = {}
                local seen_variants = {}
                for j = 1, #(item.variants or {}) do
                    local variant = item.variants[j]
                    local vname = check_name(variant.name, "variant")
                    assert(not seen_variants[vname], ("moonlift.asdl tagged union '%s' repeats variant '%s'"):format(name, vname))
                    seen_variants[vname] = true
                    variants[#variants + 1] = {
                        name = vname,
                        fields = lower_fields(variant.fields, ("variant '%s.%s'"):format(name, vname)),
                    }
                end
                decl = {
                    tag = "sum",
                    name = name,
                    unique = attr_unique(item.attrs, "tagged union '" .. name .. "'"),
                    base = normalize_tag_base(item.base_ty, "tagged union '" .. name .. "'"),
                    variants = variants,
                }
            elseif tag == "enum" then
                local name = check_name(item.name, "enum")
                assert(not RESERVED_TOPLEVEL[name], ("moonlift.asdl top-level name '%s' is reserved"):format(name))
                assert(not attr_unique(item.attrs, "enum '" .. name .. "'"),
                    ("moonlift.asdl enum '%s' does not support @unique"):format(name))
                local members = {}
                local seen_members = {}
                local next_value = 0
                for j = 1, #(item.members or {}) do
                    local member = item.members[j]
                    local mname = check_name(member.name, "enum member")
                    assert(not seen_members[mname], ("moonlift.asdl enum '%s' repeats member '%s'"):format(name, mname))
                    seen_members[mname] = true
                    local value = member.value ~= nil and eval_const_integer(member.value, ("enum '%s' member '%s'"):format(name, mname)) or next_value
                    assert(value >= 0, ("moonlift.asdl enum '%s' member '%s' must be non-negative"):format(name, mname))
                    members[#members + 1] = { name = mname, value = value }
                    next_value = value + 1
                end
                decl = {
                    tag = "enum",
                    name = name,
                    base = normalize_tag_base(item.base_ty, "enum '" .. name .. "'") or choose_unsigned_type(next_value > 0 and (next_value - 1) or 0),
                    members = members,
                }
            else
                error(("moonlift.asdl does not support top-level item '%s'"):format(tostring(tag)), 2)
            end

            assert(by_name[decl.name] == nil, ("moonlift.asdl repeats top-level name '%s'"):format(decl.name))
            by_name[decl.name] = #decls + 1
            decls[#decls + 1] = decl
        end

        return {
            tag = "schema_ir",
            decls = decls,
            by_name = by_name,
        }
    end

    local function clone_type_ref(t)
        if t.tag == "scalar" then
            return { tag = "scalar", name = t.name }
        elseif t.tag == "string" then
            return { tag = "string" }
        elseif t.tag == "bytes" then
            return { tag = "bytes" }
        elseif t.tag == "ref" then
            return { tag = "ref", name = t.name }
        elseif t.tag == "node" then
            return { tag = "node", family_id = t.family_id, name = t.name }
        elseif t.tag == "enum" then
            return { tag = "enum", enum_id = t.enum_id, name = t.name, base = t.base }
        elseif t.tag == "seq" then
            return { tag = "seq", elem = clone_type_ref(t.elem), list_id = t.list_id }
        elseif t.tag == "array" then
            return { tag = "array", len = t.len, elem = clone_type_ref(t.elem), list_id = t.list_id }
        end
        error("moonlift.asdl internal error: unknown TypeRef '" .. tostring(t.tag) .. "'", 2)
    end

    local function type_key(t)
        if t.tag == "scalar" then
            return "scalar:" .. t.name
        elseif t.tag == "string" then
            return "string"
        elseif t.tag == "bytes" then
            return "bytes"
        elseif t.tag == "node" then
            return "node:" .. t.name
        elseif t.tag == "enum" then
            return "enum:" .. t.name
        elseif t.tag == "seq" then
            return "seq(" .. type_key(t.elem) .. ")"
        elseif t.tag == "array" then
            return "array(" .. tostring(t.len) .. "," .. type_key(t.elem) .. ")"
        elseif t.tag == "ref" then
            return "ref:" .. t.name
        end
        error("moonlift.asdl internal error: unknown TypeRef for key '" .. tostring(t.tag) .. "'", 2)
    end

    local function build_plan(ir)
        local plan = {
            tag = "descriptor_plan",
            families = {},
            family_by_name = {},
            descs = {},
            desc_by_fqname = {},
            enums = {},
            enum_by_name = {},
            lists = {},
            list_by_key = {},
        }

        local decls = ir.decls
        local by_name = ir.by_name
        local alias_cache = {}
        local alias_stack = {}

        for i = 1, #decls do
            local decl = decls[i]
            if decl.tag == "enum" then
                local enum_id = #plan.enums + 1
                plan.enums[enum_id] = {
                    enum_id = enum_id,
                    name = decl.name,
                    fqname = decl.name,
                    base = decl.base,
                    members = decl.members,
                    member_by_name = false,
                }
                plan.enum_by_name[decl.name] = enum_id
            end
        end

        for i = 1, #decls do
            local decl = decls[i]
            if decl.tag == "struct" or decl.tag == "sum" then
                local family_id = #plan.families + 1
                plan.families[family_id] = {
                    family_id = family_id,
                    kind = decl.tag == "sum" and "sum" or "struct",
                    name = decl.name,
                    fqname = decl.name,
                    unique = decl.unique,
                    desc_ids = {},
                    tag_type = decl.tag == "sum" and (decl.base or choose_unsigned_type(#decl.variants > 0 and (#decl.variants - 1) or 0)) or false,
                }
                plan.family_by_name[decl.name] = family_id
            end
        end

        local function resolve_type(t)
            if t.tag == "scalar" or t.tag == "string" or t.tag == "bytes" then
                return clone_type_ref(t)
            elseif t.tag == "seq" then
                return { tag = "seq", elem = resolve_type(t.elem) }
            elseif t.tag == "array" then
                return { tag = "array", len = t.len, elem = resolve_type(t.elem) }
            elseif t.tag == "ref" then
                local idx = by_name[t.name]
                assert(idx ~= nil, ("moonlift.asdl unknown type '%s'"):format(t.name))
                local decl = decls[idx]
                if decl.tag == "alias" then
                    if alias_cache[t.name] ~= nil then
                        return clone_type_ref(alias_cache[t.name])
                    end
                    assert(not alias_stack[t.name], ("moonlift.asdl type alias cycle involving '%s'"):format(t.name))
                    alias_stack[t.name] = true
                    local out = resolve_type(decl.ty)
                    alias_stack[t.name] = nil
                    alias_cache[t.name] = clone_type_ref(out)
                    return out
                elseif decl.tag == "enum" then
                    return {
                        tag = "enum",
                        enum_id = assert(plan.enum_by_name[decl.name]),
                        name = decl.name,
                        base = decl.base,
                    }
                elseif decl.tag == "struct" or decl.tag == "sum" then
                    return {
                        tag = "node",
                        family_id = assert(plan.family_by_name[decl.name]),
                        name = decl.name,
                    }
                end
                error(("moonlift.asdl type '%s' cannot be used as a field type"):format(t.name), 2)
            end
            error("moonlift.asdl internal error: cannot resolve type '" .. tostring(t.tag) .. "'", 2)
        end

        local function ensure_list_desc(t)
            local key = type_key(t)
            local existing = plan.list_by_key[key]
            if existing ~= nil then return existing end

            local elem_type = clone_type_ref(t.elem)
            local list_id = #plan.lists + 1
            local fixed_len = t.tag == "array" and t.len or false
            local name = t.tag == "array"
                and ("[%d]%s"):format(fixed_len, type_key(elem_type))
                or ("[]" .. type_key(elem_type))

            plan.lists[list_id] = {
                list_id = list_id,
                key = key,
                kind = t.tag,
                name = name,
                elem_type = elem_type,
                fixed_len = fixed_len,
                storage = {
                    kind = "list_handle",
                    elem_kind = elem_type.tag,
                    family_id = elem_type.family_id,
                    enum_id = elem_type.enum_id,
                    fixed_len = fixed_len,
                },
                unique_mode = "canonical",
                kernels = {
                    ctor = key .. "/ctor",
                    hash = key .. "/hash",
                    eqslot = key .. "/eqslot",
                    len = key .. "/len",
                    get = key .. "/get",
                },
            }
            plan.list_by_key[key] = list_id
            return list_id
        end

        local function attach_list_ids(t)
            if t.tag == "scalar" or t.tag == "string" or t.tag == "bytes" or t.tag == "node" or t.tag == "enum" then
                return clone_type_ref(t)
            elseif t.tag == "seq" then
                local elem = attach_list_ids(t.elem)
                local out = { tag = "seq", elem = elem }
                out.list_id = ensure_list_desc(out)
                return out
            elseif t.tag == "array" then
                local elem = attach_list_ids(t.elem)
                local out = { tag = "array", len = t.len, elem = elem }
                out.list_id = ensure_list_desc(out)
                return out
            end
            error("moonlift.asdl internal error: cannot attach list ids to '" .. tostring(t.tag) .. "'", 2)
        end

        local function storage_for_type(t)
            if t.tag == "scalar" then
                return { kind = "inline_scalar", scalar = t.name }
            elseif t.tag == "string" then
                return { kind = "leaf_string" }
            elseif t.tag == "bytes" then
                return { kind = "leaf_bytes" }
            elseif t.tag == "enum" then
                return { kind = "enum_scalar", enum_id = t.enum_id, base = t.base }
            elseif t.tag == "node" then
                return { kind = "node_handle", family_id = t.family_id }
            elseif t.tag == "seq" or t.tag == "array" then
                return { kind = "list_handle", list_id = t.list_id, fixed_len = t.tag == "array" and t.len or false }
            end
            error("moonlift.asdl internal error: no storage for type '" .. tostring(t.tag) .. "'", 2)
        end

        local function planned_fields(fields, owner)
            local out = {}
            assert(#fields <= 52, ("moonlift.asdl %s has too many fields for v1 (%d > 52)"):format(owner, #fields))
            for i = 1, #fields do
                local field = fields[i]
                local resolved = attach_list_ids(resolve_type(field.type))
                out[i] = {
                    index = i,
                    name = field.name,
                    type = resolved,
                    storage = storage_for_type(resolved),
                    with_bit = 2 ^ (i - 1),
                }
            end
            return out
        end

        local function kernel_keys_for(fqname, fields, singleton)
            if singleton then
                return {
                    singleton = fqname .. "/singleton",
                }
            end
            local getters = {}
            for i = 1, #fields do
                getters[fields[i].name] = fqname .. "/get/" .. fields[i].name
            end
            return {
                ctor = fqname .. "/ctor",
                hash = fqname .. "/hash",
                eqslot = fqname .. "/eqslot",
                getters = getters,
                with_ = fqname .. "/with",
            }
        end

        for i = 1, #decls do
            local decl = decls[i]
            if decl.tag == "struct" then
                local family_id = assert(plan.family_by_name[decl.name])
                local fields = planned_fields(decl.fields, "struct '" .. decl.name .. "'")
                local desc_id = #plan.descs + 1
                local fqname = decl.name
                local desc = {
                    desc_id = desc_id,
                    family_id = family_id,
                    kind = "struct",
                    name = decl.name,
                    fqname = fqname,
                    unique = decl.unique,
                    tag = false,
                    singleton = false,
                    fields = fields,
                    kernels = kernel_keys_for(fqname, fields, false),
                }
                plan.descs[desc_id] = desc
                plan.desc_by_fqname[fqname] = desc_id
                plan.families[family_id].desc_ids[#plan.families[family_id].desc_ids + 1] = desc_id
            elseif decl.tag == "sum" then
                local family_id = assert(plan.family_by_name[decl.name])
                for tag = 1, #decl.variants do
                    local variant = decl.variants[tag]
                    local fields = planned_fields(variant.fields, ("variant '%s.%s'"):format(decl.name, variant.name))
                    local fqname = decl.name .. "." .. variant.name
                    local desc_id = #plan.descs + 1
                    local desc = {
                        desc_id = desc_id,
                        family_id = family_id,
                        kind = "variant",
                        name = variant.name,
                        fqname = fqname,
                        unique = decl.unique,
                        tag = tag - 1,
                        singleton = #fields == 0,
                        fields = fields,
                        kernels = kernel_keys_for(fqname, fields, #fields == 0),
                    }
                    plan.descs[desc_id] = desc
                    plan.desc_by_fqname[fqname] = desc_id
                    plan.families[family_id].desc_ids[#plan.families[family_id].desc_ids + 1] = desc_id
                end
            end
        end

        for i = 1, #plan.enums do
            local member_by_name = {}
            for j = 1, #plan.enums[i].members do
                local member = plan.enums[i].members[j]
                member_by_name[member.name] = member.value
            end
            plan.enums[i].member_by_name = member_by_name
        end

        return plan
    end

    local DescObjMT = {}
    local ListDescObjMT = {}
    local FamilyMT = {
        __tostring = function(self)
            return "<asdl family " .. tostring(rawget(self, "__name")) .. ">"
        end,
    }
    local EnumMT = {
        __tostring = function(self)
            return "<asdl enum " .. tostring(rawget(self, "__name")) .. ">"
        end,
    }

    local function instantiate_runtime(ir, plan)
        local runtime = {
            __tag = "asdl_runtime",
            __ir = ir,
            __plan = plan,
            __families = {},
            __descs = {},
            __lists = {},
            __enums = {},
            __stores = {},
            __list_stores = {},
            __interns = {},
            __list_interns = {},
            __singletons = {},
            __handle_meta = {},
            __wrapper_cache = setmetatable({}, { __mode = "v" }),
            __next_handle = 1,
            __kernels = {},
        }

        local function alloc_handle(kind, meta)
            local h = runtime.__next_handle
            runtime.__next_handle = h + 1
            meta.kind = kind
            runtime.__handle_meta[h] = meta
            return h
        end

        local function wrap_handle(handle)
            local wrapper = runtime.__wrapper_cache[handle]
            if wrapper ~= nil then return wrapper end
            local meta = runtime.__handle_meta[handle]
            assert(meta ~= nil, "moonlift.asdl internal error: unknown handle")
            if meta.kind == "node" then
                wrapper = setmetatable({ __h = handle }, runtime.__descs[meta.desc_id])
            else
                wrapper = setmetatable({ __h = handle }, runtime.__lists[meta.list_id])
            end
            runtime.__wrapper_cache[handle] = wrapper
            return wrapper
        end

        local function list_slot(list_desc, handle)
            local meta = runtime.__handle_meta[handle]
            assert(meta ~= nil and meta.kind == "list" and meta.list_id == list_desc.__list_id,
                "moonlift.asdl internal error: invalid list handle")
            return runtime.__list_stores[list_desc.__list_id].slots[meta.slot]
        end

        local function node_slot(desc, handle)
            local meta = runtime.__handle_meta[handle]
            assert(meta ~= nil and meta.kind == "node" and meta.desc_id == desc.__desc_id,
                "moonlift.asdl internal error: invalid node handle")
            return runtime.__stores[desc.__desc_id].slots[meta.slot]
        end

        local function type_key_for_value(v)
            local tv = type(v)
            if tv ~= "table" then return serialize_atom(v) end
            local mt = getmetatable(v)
            if mt and rawget(mt, "__tag") == "asdl_desc" then
                return "h:" .. tostring(rawget(v, "__h"))
            elseif mt and rawget(mt, "__tag") == "asdl_list_desc" then
                return "l:" .. tostring(rawget(v, "__h"))
            end
            error("moonlift.asdl internal error: unsupported value in structural key", 2)
        end

        local normalize_value
        local render_list

        local function export_value(type_ref, stored)
            if type_ref.tag == "node" or type_ref.tag == "seq" or type_ref.tag == "array" then
                return wrap_handle(stored)
            end
            return stored
        end

        local function list_structural_key(list_desc, values)
            local parts = { "list", tostring(list_desc.__list_id), tostring(#values) }
            for i = 1, #values do
                parts[#parts + 1] = type_key_for_value(export_value(list_desc.__elem_type, values[i]))
            end
            return tconcat(parts, "|")
        end

        local function ctor_list_raw(list_desc, values)
            local intern = runtime.__list_interns[list_desc.__list_id]
            local key = list_structural_key(list_desc, values)
            local hit = intern[key]
            if hit ~= nil then return hit end

            local store = runtime.__list_stores[list_desc.__list_id]
            local slot = #store.slots + 1
            local copied = {}
            for i = 1, #values do copied[i] = values[i] end
            store.slots[slot] = { values = copied }
            local handle = alloc_handle("list", { list_id = list_desc.__list_id, slot = slot })
            intern[key] = handle
            return handle
        end

        local function check_array_keys(values, where)
            local n = #values
            for i = 1, n do
                assert(values[i] ~= nil, ("moonlift.asdl %s requires a dense array"):format(where))
            end
            for k, _ in pairs(values) do
                assert(type(k) == "number" and k >= 1 and k <= n and k == math_floor(k),
                    ("moonlift.asdl %s expects only dense array keys"):format(where))
            end
            return n
        end

        local function normalize_scalar(type_name, value, where)
            if type_name == "bool" then
                assert(type(value) == "boolean", ("moonlift.asdl %s expects bool"):format(where))
                return value
            elseif INTEGER_SCALARS[type_name] then
                assert(is_integral_number(value), ("moonlift.asdl %s expects integer %s"):format(where, type_name))
                return value
            else
                assert(type(value) == "number", ("moonlift.asdl %s expects number %s"):format(where, type_name))
                return value
            end
        end

        normalize_value = function(type_ref, value, where)
            if type_ref.tag == "scalar" then
                return normalize_scalar(type_ref.name, value, where)
            elseif type_ref.tag == "string" or type_ref.tag == "bytes" then
                assert(type(value) == "string", ("moonlift.asdl %s expects %s"):format(where, type_ref.tag))
                return value
            elseif type_ref.tag == "enum" then
                assert(is_integral_number(value), ("moonlift.asdl %s expects enum %s scalar value"):format(where, type_ref.name))
                return value
            elseif type_ref.tag == "node" then
                local mt = type(value) == "table" and getmetatable(value) or nil
                assert(mt ~= nil and rawget(mt, "__tag") == "asdl_desc", ("moonlift.asdl %s expects %s node"):format(where, type_ref.name))
                assert(rawget(mt, "__family_id") == type_ref.family_id, ("moonlift.asdl %s expects %s node"):format(where, type_ref.name))
                return rawget(value, "__h")
            elseif type_ref.tag == "seq" or type_ref.tag == "array" then
                local list_desc = runtime.__lists[type_ref.list_id]
                local mt = type(value) == "table" and getmetatable(value) or nil
                if mt ~= nil and rawget(mt, "__tag") == "asdl_list_desc" then
                    assert(rawget(mt, "__list_id") == list_desc.__list_id,
                        ("moonlift.asdl %s expects list type %s"):format(where, list_desc.__name))
                    return rawget(value, "__h")
                end
                assert(is_plain_table(value), ("moonlift.asdl %s expects a plain Lua array or canonical list"):format(where))
                local n = check_array_keys(value, where)
                if type_ref.tag == "array" then
                    assert(n == type_ref.len, ("moonlift.asdl %s expects exactly %d elements"):format(where, type_ref.len))
                end
                local stored = {}
                for i = 1, n do
                    stored[i] = normalize_value(list_desc.__elem_type, value[i], ("%s[%d]"):format(where, i))
                end
                return ctor_list_raw(list_desc, stored)
            end
            error("moonlift.asdl internal error: cannot normalize type '" .. tostring(type_ref.tag) .. "'", 2)
        end

        local function desc_structural_key(desc, values)
            local parts = { "node", tostring(desc.__desc_id) }
            for i = 1, #values do
                local field = desc.__fields[i]
                parts[#parts + 1] = field.name
                parts[#parts + 1] = type_key_for_value(export_value(field.type, values[i]))
            end
            return tconcat(parts, "|")
        end

        local function ctor_desc_raw(desc, values)
            local singleton = rawget(desc, "__singleton_handle")
            if singleton then return singleton end

            local store = runtime.__stores[desc.__desc_id]
            local intern = runtime.__interns[desc.__desc_id]
            if intern ~= false then
                local key = desc_structural_key(desc, values)
                local hit = intern[key]
                if hit ~= nil then return hit end
                local slot = #store.slots + 1
                local copied = {}
                for i = 1, #values do copied[i] = values[i] end
                store.slots[slot] = { values = copied }
                local handle = alloc_handle("node", { desc_id = desc.__desc_id, slot = slot })
                intern[key] = handle
                return handle
            end

            local slot = #store.slots + 1
            local copied = {}
            for i = 1, #values do copied[i] = values[i] end
            store.slots[slot] = { values = copied }
            return alloc_handle("node", { desc_id = desc.__desc_id, slot = slot })
        end

        local function desc_ctor(desc, spec)
            assert(is_plain_table(spec), ("moonlift.asdl constructor for '%s' expects one plain Lua table"):format(desc.__fqname))
            local values = {}
            for k, _ in pairs(spec) do
                assert(rawget(desc, "__field_index")[k] ~= nil,
                    ("moonlift.asdl constructor for '%s' got unknown field '%s'"):format(desc.__fqname, tostring(k)))
            end
            for i = 1, #desc.__fields do
                local field = desc.__fields[i]
                local value = spec[field.name]
                assert(value ~= nil, ("moonlift.asdl constructor for '%s' is missing field '%s'"):format(desc.__fqname, field.name))
                values[i] = normalize_value(field.type, value, desc.__fqname .. "." .. field.name)
            end
            return wrap_handle(desc.__ctor_raw(values))
        end

        local function desc_with(desc, node, overrides)
            assert(is_plain_table(overrides), ("moonlift.asdl T.with on '%s' expects one plain Lua table"):format(desc.__fqname))
            local slot = node_slot(desc, rawget(node, "__h"))
            local values = {}
            for k, _ in pairs(overrides) do
                assert(rawget(desc, "__field_index")[k] ~= nil,
                    ("moonlift.asdl T.with on '%s' got unknown field '%s'"):format(desc.__fqname, tostring(k)))
            end
            for i = 1, #desc.__fields do
                local field = desc.__fields[i]
                local ov = overrides[field.name]
                if ov ~= nil then
                    values[i] = normalize_value(field.type, ov, desc.__fqname .. "." .. field.name)
                else
                    values[i] = slot.values[i]
                end
            end
            return wrap_handle(desc.__ctor_raw(values))
        end

        local function render_node(node, seen)
            local desc = getmetatable(node)
            if seen[node] then return desc.__fqname .. "{...}" end
            seen[node] = true
            if #desc.__fields == 0 then
                seen[node] = nil
                return desc.__fqname
            end
            local parts = {}
            for i = 1, #desc.__fields do
                local field = desc.__fields[i]
                local value = desc.__getters[field.name](node)
                if type(value) == "table" then
                    local mt = getmetatable(value)
                    if mt and rawget(mt, "__tag") == "asdl_desc" then
                        value = render_node(value, seen)
                    elseif mt and rawget(mt, "__tag") == "asdl_list_desc" then
                        value = render_list(value, seen)
                    else
                        value = tostring(value)
                    end
                else
                    value = pretty_atom(value)
                end
                parts[#parts + 1] = field.name .. " = " .. value
            end
            seen[node] = nil
            return desc.__fqname .. " { " .. tconcat(parts, ", ") .. " }"
        end

        render_list = function(list_value, seen)
            local list_desc = getmetatable(list_value)
            if seen[list_value] then return list_desc.__name .. "[...]" end
            seen[list_value] = true
            local slot = list_slot(list_desc, rawget(list_value, "__h"))
            local parts = {}
            for i = 1, #slot.values do
                local value = export_value(list_desc.__elem_type, slot.values[i])
                if type(value) == "table" then
                    local mt = getmetatable(value)
                    if mt and rawget(mt, "__tag") == "asdl_desc" then
                        value = render_node(value, seen)
                    elseif mt and rawget(mt, "__tag") == "asdl_list_desc" then
                        value = render_list(value, seen)
                    else
                        value = tostring(value)
                    end
                else
                    value = pretty_atom(value)
                end
                parts[#parts + 1] = value
            end
            seen[list_value] = nil
            return "[" .. tconcat(parts, ", ") .. "]"
        end

        local function runtime_classof(value)
            if type(value) ~= "table" then return nil end
            local mt = getmetatable(value)
            if mt == nil then return nil end
            local tag = rawget(mt, "__tag")
            if tag == "asdl_desc" or tag == "asdl_list_desc" then
                return mt
            end
            return nil
        end

        local function runtime_is(value, target)
            local class = runtime_classof(value)
            if class == nil then return false end
            if type(target) == "table" then
                local tag = rawget(target, "__tag")
                if tag == "asdl_desc" or tag == "asdl_list_desc" then
                    return class == target
                elseif tag == "asdl_family" then
                    return rawget(class, "__family_id") == rawget(target, "__family_id")
                end
                local tclass = runtime_classof(target)
                if tclass ~= nil then
                    return value == target
                end
            end
            return false
        end

        local function runtime_with(value, overrides)
            local desc = runtime_classof(value)
            assert(desc ~= nil and rawget(desc, "__tag") == "asdl_desc", "moonlift.asdl T.with expects an ASDL node")
            return desc.__with(value, overrides)
        end

        runtime.with = runtime_with
        runtime.classof = runtime_classof
        runtime.is = runtime_is

        for i = 1, #plan.enums do
            local eplan = plan.enums[i]
            local enum_obj = {
                __tag = "asdl_enum",
                __runtime = runtime,
                __plan = eplan,
                __name = eplan.name,
                __base = eplan.base,
            }
            for j = 1, #eplan.members do
                local member = eplan.members[j]
                enum_obj[member.name] = member.value
            end
            setmetatable(enum_obj, EnumMT)
            runtime.__enums[i] = enum_obj
            rawset(runtime, eplan.name, enum_obj)
        end

        for i = 1, #plan.families do
            local fplan = plan.families[i]
            local family = {
                __tag = "asdl_family",
                __runtime = runtime,
                __plan = fplan,
                __family_id = fplan.family_id,
                __name = fplan.name,
                __variants = {},
            }
            setmetatable(family, FamilyMT)
            runtime.__families[i] = family
            if fplan.kind == "sum" then
                rawset(runtime, fplan.name, family)
            end
        end

        for i = 1, #plan.lists do
            local lplan = plan.lists[i]
            runtime.__list_stores[i] = { slots = {} }
            runtime.__list_interns[i] = {}
            local list_desc = {
                __tag = "asdl_list_desc",
                __runtime = runtime,
                __plan = lplan,
                __list_id = lplan.list_id,
                __name = lplan.name,
                __elem_type = clone_type_ref(lplan.elem_type),
            }
            list_desc.__ctor_raw = function(values)
                return ctor_list_raw(list_desc, values)
            end
            list_desc.__len = function(self)
                local slot = list_slot(list_desc, rawget(self, "__h"))
                return #slot.values
            end
            list_desc.__index = function(self, key)
                if type(key) == "number" then
                    local slot = list_slot(list_desc, rawget(self, "__h"))
                    assert(key == math_floor(key) and key >= 1 and key <= #slot.values,
                        ("moonlift.asdl list index %s out of bounds"):format(tostring(key)))
                    return export_value(list_desc.__elem_type, slot.values[key])
                end
                return nil
            end
            list_desc.__newindex = function()
                error("moonlift.asdl lists are immutable", 2)
            end
            list_desc.__tostring = function(self)
                return render_list(self, {})
            end
            setmetatable(list_desc, ListDescObjMT)
            runtime.__lists[i] = list_desc
            runtime.__kernels[lplan.kernels.ctor] = list_desc.__ctor_raw
            runtime.__kernels[lplan.kernels.len] = function(handle)
                return #list_slot(list_desc, handle).values
            end
            runtime.__kernels[lplan.kernels.get] = function(handle, index)
                return list_slot(list_desc, handle).values[index]
            end
        end

        for i = 1, #plan.descs do
            local dplan = plan.descs[i]
            runtime.__stores[i] = { slots = {} }
            runtime.__interns[i] = (dplan.unique or dplan.singleton) and {} or false

            local family = runtime.__families[dplan.family_id]
            local desc = {
                __tag = "asdl_desc",
                __runtime = runtime,
                __plan = dplan,
                __desc_id = dplan.desc_id,
                __family = family,
                __family_id = dplan.family_id,
                __name = dplan.name,
                __fqname = dplan.fqname,
                __fields = dplan.fields,
                __field_index = {},
                __with_bits = {},
                __singleton_handle = nil,
                __getters = {},
            }
            for j = 1, #dplan.fields do
                local field = dplan.fields[j]
                desc.__field_index[field.name] = j
                desc.__with_bits[field.name] = field.with_bit
            end

            desc.__ctor_raw = function(values)
                return ctor_desc_raw(desc, values)
            end
            desc.__ctor = function(spec)
                return desc_ctor(desc, spec)
            end
            desc.__with = function(node, overrides)
                return desc_with(desc, node, overrides)
            end
            for j = 1, #dplan.fields do
                local field = dplan.fields[j]
                desc.__getters[field.name] = function(node)
                    local slot = node_slot(desc, rawget(node, "__h"))
                    return export_value(field.type, slot.values[field.index])
                end
            end

            desc.__index = function(self, key)
                local getter = desc.__getters[key]
                if getter ~= nil then return getter(self) end
                if key == "with" then
                    return function(node, overrides)
                        return runtime_with(node, overrides)
                    end
                elseif key == "is" then
                    return function(node, target)
                        return runtime_is(node, target)
                    end
                elseif key == "classof" then
                    return function(node)
                        return runtime_classof(node)
                    end
                end
                return nil
            end
            desc.__newindex = function()
                error("moonlift.asdl values are immutable", 2)
            end
            desc.__tostring = function(self)
                return render_node(self, {})
            end

            setmetatable(desc, DescObjMT)
            runtime.__descs[i] = desc
            runtime.__kernels[dplan.singleton and dplan.kernels.singleton or dplan.kernels.ctor] = desc.__ctor_raw
            if dplan.kernels.getters then
                for name, key in pairs(dplan.kernels.getters) do
                    local getter = desc.__getters[name]
                    runtime.__kernels[key] = function(handle)
                        return node_slot(desc, handle).values[desc.__field_index[name]]
                    end
                end
            end
            if not dplan.singleton then
                runtime.__kernels[dplan.kernels.with_] = function(handle, overrides)
                    return rawget(desc_with(desc, wrap_handle(handle), overrides), "__h")
                end
            end

            family.__variants[dplan.name] = desc
            if plan.families[dplan.family_id].kind == "struct" then
                rawset(runtime, dplan.name, desc)
            elseif not dplan.singleton then
                family[dplan.name] = desc
            end
        end

        for i = 1, #plan.descs do
            local desc = runtime.__descs[i]
            if #desc.__fields == 0 then
                local handle = alloc_handle("node", { desc_id = desc.__desc_id, slot = 0 })
                desc.__singleton_handle = handle
                local wrapper = wrap_handle(handle)
                runtime.__singletons[desc.__desc_id] = wrapper
                local family = desc.__family
                family[desc.__name] = wrapper
            end
        end

        return runtime
    end

    DescObjMT.__call = function(self, spec)
        return self.__ctor(spec)
    end

    DescObjMT.__tostring = function(self)
        return "<asdl desc " .. tostring(rawget(self, "__fqname")) .. ">"
    end

    ListDescObjMT.__tostring = function(self)
        return "<asdl list desc " .. tostring(rawget(self, "__name")) .. ">"
    end

    local function compile_from_ast(module_ast)
        local ir = lower_module_ast(module_ast)
        local plan = build_plan(ir)
        return instantiate_runtime(ir, plan)
    end

    local function compile(source, host_env)
        local _ = host_env or caller_env(2)
        local ast = parse.module(source)
        return compile_from_ast(ast)
    end

    return {
        compile = compile,
        lower_ir = lower_module_ast,
        plan = build_plan,
        compile_ast = compile_from_ast,
        caller_env = caller_env,
    }
end
