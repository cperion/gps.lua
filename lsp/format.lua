-- lsp/format.lua
--
-- AST pretty-printer boundary.
-- pvm.phase("format_file"): FormatQuery(file, options, range, has_range) -> FormatResult(text, range, has_range)

package.path = "./?.lua;./?/init.lua;" .. package.path

local pvm = require("pvm")

local M = {}

function M.new(context)
    local C = context.Lua

    local BIN_PREC = {
        ["or"] = 1,
        ["and"] = 2,
        ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["=="] = 3, ["~="] = 3,
        [".."] = 4,
        ["+"] = 5, ["-"] = 5,
        ["*"] = 6, ["/"] = 6, ["%"] = 6, ["//"] = 6,
        ["^"] = 7,
    }

    local RIGHT_ASSOC = { ["^"] = true, [".."] = true }

    local function qstr(s)
        return string.format("%q", s or "")
    end

    local function type_expr_to_string(t)
        if not t then return "any" end
        local k = t.kind
        if k == "TAny" then return "any" end
        if k == "TUnknown" then return "unknown" end
        if k == "TNil" then return "nil" end
        if k == "TBoolean" then return "boolean" end
        if k == "TNumber" then return "number" end
        if k == "TString" then return "string" end
        if k == "TNamed" then return t.name end
        if k == "TLiteralString" then return qstr(t.value) end
        if k == "TLiteralNumber" then return t.value end
        if k == "TOptional" then return type_expr_to_string(t.inner) .. "?" end
        if k == "TArray" then return type_expr_to_string(t.item) .. "[]" end
        if k == "TGeneric" then return t.name end
        if k == "TParen" then return "(" .. type_expr_to_string(t.inner) .. ")" end
        if k == "TVararg" then return "..." .. type_expr_to_string(t.inner) end
        if k == "TTuple" then
            local out = {}
            for i = 1, #t.items do out[i] = type_expr_to_string(t.items[i]) end
            return table.concat(out, ", ")
        end
        if k == "TUnion" then
            local out = {}
            for i = 1, #t.parts do out[i] = type_expr_to_string(t.parts[i]) end
            return table.concat(out, "|")
        end
        if k == "TIntersect" then
            local out = {}
            for i = 1, #t.parts do out[i] = type_expr_to_string(t.parts[i]) end
            return table.concat(out, "&")
        end
        if k == "TMap" then
            return "{" .. "[" .. type_expr_to_string(t.key) .. "]: " .. type_expr_to_string(t.value) .. "}"
        end
        if k == "TTable" then
            local out = {}
            for i = 1, #t.fields do
                local f = t.fields[i]
                out[i] = f.name .. (f.optional and "?" or "") .. ": " .. type_expr_to_string(f.typ)
            end
            return "{" .. table.concat(out, ", ") .. "}"
        end
        if k == "TFunc" then
            local params, rets = {}, {}
            local sig = t.sig
            for i = 1, #sig.params do params[i] = type_expr_to_string(sig.params[i]) end
            for i = 1, #sig.returns do rets[i] = type_expr_to_string(sig.returns[i]) end
            local ret = (#rets > 0) and table.concat(rets, ", ") or "nil"
            return "fun(" .. table.concat(params, ", ") .. "): " .. ret
        end
        return k
    end

    local function doc_tag_lines(tag)
        local k = tag.kind
        if k == "ClassTag" then
            local s = "---@class " .. tag.name
            if #tag.extends > 0 then
                local ex = {}
                for i = 1, #tag.extends do ex[i] = type_expr_to_string(tag.extends[i]) end
                s = s .. " : " .. table.concat(ex, ", ")
            end
            return { s }
        end
        if k == "FieldTag" then
            return { "---@field " .. tag.name .. (tag.optional and "?" or "") .. " " .. type_expr_to_string(tag.typ) }
        end
        if k == "ParamTag" then
            return { "---@param " .. tag.name .. " " .. type_expr_to_string(tag.typ) }
        end
        if k == "ReturnTag" then
            local vals = {}
            for i = 1, #tag.values do vals[i] = type_expr_to_string(tag.values[i]) end
            return { "---@return " .. table.concat(vals, ", ") }
        end
        if k == "TypeTag" then
            return { "---@type " .. type_expr_to_string(tag.typ) }
        end
        if k == "AliasTag" then
            return { "---@alias " .. tag.name .. " " .. type_expr_to_string(tag.typ) }
        end
        if k == "GenericTag" then
            local s = "---@generic " .. tag.name
            if #tag.bounds > 0 then
                local bs = {}
                for i = 1, #tag.bounds do bs[i] = type_expr_to_string(tag.bounds[i]) end
                s = s .. " : " .. table.concat(bs, "|")
            end
            return { s }
        end
        if k == "OverloadTag" then
            local p, r = {}, {}
            for i = 1, #tag.sig.params do p[i] = type_expr_to_string(tag.sig.params[i]) end
            for i = 1, #tag.sig.returns do r[i] = type_expr_to_string(tag.sig.returns[i]) end
            return { "---@overload fun(" .. table.concat(p, ", ") .. "): " .. table.concat(r, ", ") }
        end
        if k == "CastTag" then
            return { "---@cast " .. type_expr_to_string(tag.typ) }
        end
        if k == "MetaTag" then
            return { "---@" .. tag.name .. (tag.text ~= "" and (" " .. tag.text) or "") }
        end
        return { "---" }
    end

    local render_expr, render_stmt, render_block, render_func_body, render_lvalue

    function render_lvalue(lv)
        if lv.kind == "LName" then return lv.name end
        if lv.kind == "LField" then return render_expr(lv.base, 9) .. "." .. lv.key end
        if lv.kind == "LIndex" then return render_expr(lv.base, 9) .. "[" .. render_expr(lv.key, 0) .. "]" end
        if lv.kind == "LMethod" then return render_expr(lv.base, 9) .. ":" .. lv.method end
        return "_"
    end

    function render_func_body(body, level, unit)
        local params = {}
        for i = 1, #body.params do params[i] = body.params[i].name end
        if body.vararg then params[#params + 1] = "..." end

        local head = "(" .. table.concat(params, ", ") .. ")"
        local lines = render_block(body.body, level + 1, unit)
        local out = { head }
        for i = 1, #lines do out[#out + 1] = lines[i] end
        out[#out + 1] = string.rep(unit, level) .. "end"
        return out
    end

    function render_expr(e, parent_prec)
        if not e then return "nil" end
        local k = e.kind

        if k == "Nil" then return "nil" end
        if k == "True" then return "true" end
        if k == "False" then return "false" end
        if k == "Number" then return e.value end
        if k == "String" then return qstr(e.value) end
        if k == "Vararg" then return "..." end
        if k == "NameRef" then return e.name end
        if k == "Field" then return render_expr(e.base, 9) .. "." .. e.key end
        if k == "Index" then return render_expr(e.base, 9) .. "[" .. render_expr(e.key, 0) .. "]" end
        if k == "Paren" then return "(" .. render_expr(e.inner, 0) .. ")" end

        if k == "Unary" then
            local p = 8
            local s = (e.op == "not") and ("not " .. render_expr(e.value, p)) or (e.op .. render_expr(e.value, p))
            if parent_prec and p < parent_prec then return "(" .. s .. ")" end
            return s
        end

        if k == "Binary" then
            local p = BIN_PREC[e.op] or 1
            local lp = RIGHT_ASSOC[e.op] and p or (p + 1)
            local rp = RIGHT_ASSOC[e.op] and (p + 1) or p
            local s = render_expr(e.lhs, lp) .. " " .. e.op .. " " .. render_expr(e.rhs, rp)
            if parent_prec and p < parent_prec then return "(" .. s .. ")" end
            return s
        end

        if k == "Call" then
            local args = {}
            for i = 1, #e.args do args[i] = render_expr(e.args[i], 0) end
            return render_expr(e.callee, 9) .. "(" .. table.concat(args, ", ") .. ")"
        end

        if k == "MethodCall" then
            local args = {}
            for i = 1, #e.args do args[i] = render_expr(e.args[i], 0) end
            return render_expr(e.recv, 9) .. ":" .. e.method .. "(" .. table.concat(args, ", ") .. ")"
        end

        if k == "FunctionExpr" then
            local body_lines = render_func_body(e.body, 0, "    ")
            return "function" .. body_lines[1] .. "\n" .. table.concat(body_lines, "\n", 2)
        end

        if k == "TableCtor" then
            if #e.fields == 0 then return "{}" end
            local f = {}
            for i = 1, #e.fields do
                local ff = e.fields[i]
                if ff.kind == "ArrayField" then
                    f[i] = render_expr(ff.value, 0)
                elseif ff.kind == "PairField" then
                    f[i] = "[" .. render_expr(ff.key, 0) .. "] = " .. render_expr(ff.value, 0)
                else
                    f[i] = ff.key .. " = " .. render_expr(ff.value, 0)
                end
            end
            return "{ " .. table.concat(f, ", ") .. " }"
        end

        return "nil"
    end

    function render_stmt(s, level, unit)
        local ind = string.rep(unit, level)
        local out = {}

        if s.kind == "LocalAssign" then
            local names, vals = {}, {}
            for i = 1, #s.names do names[i] = s.names[i].value end
            for i = 1, #s.values do vals[i] = render_expr(s.values[i], 0) end
            local rhs = (#vals > 0) and (" = " .. table.concat(vals, ", ")) or ""
            out[1] = ind .. "local " .. table.concat(names, ", ") .. rhs
            return out
        end

        if s.kind == "Assign" then
            local lhs, rhs = {}, {}
            for i = 1, #s.lhs do lhs[i] = render_lvalue(s.lhs[i]) end
            for i = 1, #s.rhs do rhs[i] = render_expr(s.rhs[i], 0) end
            out[1] = ind .. table.concat(lhs, ", ") .. " = " .. table.concat(rhs, ", ")
            return out
        end

        if s.kind == "LocalFunction" then
            local body = render_func_body(s.body, level, unit)
            out[1] = ind .. "local function " .. s.name .. body[1]
            for i = 2, #body do out[#out + 1] = body[i] end
            return out
        end

        if s.kind == "Function" then
            local body = render_func_body(s.body, level, unit)
            out[1] = ind .. "function " .. render_lvalue(s.name) .. body[1]
            for i = 2, #body do out[#out + 1] = body[i] end
            return out
        end

        if s.kind == "Return" then
            if #s.values == 0 then out[1] = ind .. "return"
            else
                local vals = {}
                for i = 1, #s.values do vals[i] = render_expr(s.values[i], 0) end
                out[1] = ind .. "return " .. table.concat(vals, ", ")
            end
            return out
        end

        if s.kind == "CallStmt" then
            local args = {}
            for i = 1, #s.args do args[i] = render_expr(s.args[i], 0) end
            out[1] = ind .. render_expr(s.callee, 9) .. "(" .. table.concat(args, ", ") .. ")"
            return out
        end

        if s.kind == "If" then
            for i = 1, #s.arms do
                local arm = s.arms[i]
                if i == 1 then out[#out + 1] = ind .. "if " .. render_expr(arm.cond, 0) .. " then"
                else out[#out + 1] = ind .. "elseif " .. render_expr(arm.cond, 0) .. " then" end
                local inner = render_block(arm.body, level + 1, unit)
                for j = 1, #inner do out[#out + 1] = inner[j] end
            end
            if s.else_block and #s.else_block.items > 0 then
                out[#out + 1] = ind .. "else"
                local inner = render_block(s.else_block, level + 1, unit)
                for j = 1, #inner do out[#out + 1] = inner[j] end
            end
            out[#out + 1] = ind .. "end"
            return out
        end

        if s.kind == "While" then
            out[#out + 1] = ind .. "while " .. render_expr(s.cond, 0) .. " do"
            local inner = render_block(s.body, level + 1, unit)
            for i = 1, #inner do out[#out + 1] = inner[i] end
            out[#out + 1] = ind .. "end"
            return out
        end

        if s.kind == "Repeat" then
            out[#out + 1] = ind .. "repeat"
            local inner = render_block(s.body, level + 1, unit)
            for i = 1, #inner do out[#out + 1] = inner[i] end
            out[#out + 1] = ind .. "until " .. render_expr(s.cond, 0)
            return out
        end

        if s.kind == "ForNum" then
            out[#out + 1] = ind .. "for " .. s.name .. " = " .. render_expr(s.init, 0) .. ", " .. render_expr(s.limit, 0) .. ", " .. render_expr(s.step, 0) .. " do"
            local inner = render_block(s.body, level + 1, unit)
            for i = 1, #inner do out[#out + 1] = inner[i] end
            out[#out + 1] = ind .. "end"
            return out
        end

        if s.kind == "ForIn" then
            local names, it = {}, {}
            for i = 1, #s.names do names[i] = s.names[i].value end
            for i = 1, #s.iter do it[i] = render_expr(s.iter[i], 0) end
            out[#out + 1] = ind .. "for " .. table.concat(names, ", ") .. " in " .. table.concat(it, ", ") .. " do"
            local inner = render_block(s.body, level + 1, unit)
            for i = 1, #inner do out[#out + 1] = inner[i] end
            out[#out + 1] = ind .. "end"
            return out
        end

        if s.kind == "Do" then
            out[#out + 1] = ind .. "do"
            local inner = render_block(s.body, level + 1, unit)
            for i = 1, #inner do out[#out + 1] = inner[i] end
            out[#out + 1] = ind .. "end"
            return out
        end

        if s.kind == "Break" then return { ind .. "break" } end
        if s.kind == "Goto" then return { ind .. "goto " .. s.label } end
        if s.kind == "Label" then return { ind .. "::" .. s.label .. "::" } end

        return { ind .. "--[[ unsupported stmt: " .. tostring(s.kind) .. " ]]" }
    end

    function render_block(block, level, unit)
        local out = {}
        for i = 1, #block.items do
            local item = block.items[i]
            for d = 1, #item.docs do
                local db = item.docs[d]
                for t = 1, #db.tags do
                    local lines = doc_tag_lines(db.tags[t])
                    for li = 1, #lines do
                        out[#out + 1] = string.rep(unit, level) .. lines[li]
                    end
                end
            end
            local stmt_lines = render_stmt(item.stmt, level, unit)
            for j = 1, #stmt_lines do out[#out + 1] = stmt_lines[j] end
        end
        return out
    end

    local format_file = pvm.phase("format_file", function(q)
        local opts = q.options
        local size = tonumber(opts.tab_size) or 4
        if size < 1 then size = 4 end
        local unit = opts.insert_spaces and string.rep(" ", size) or "\t"

        local items = {}
        for i = 1, #q.doc.items do items[i] = q.doc.items[i].syntax end
        local lines = render_block(C.Block(items), 0, unit)

        if opts.trim_trailing_ws then
            for i = 1, #lines do lines[i] = lines[i]:gsub("[ \t]+$", "") end
        end

        local function join(ls)
            local text = table.concat(ls, "\n")
            if opts.insert_final_newline and text ~= "" and text:sub(-1) ~= "\n" then
                text = text .. "\n"
            end
            return text
        end

        if q.has_range then
            local total = #lines
            if total == 0 then
                return C.FormatResult("", C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0)), true)
            end

            local sline = q.range.start.line or 0
            local eline = q.range.stop.line or sline
            if sline < 0 then sline = 0 end
            if eline < sline then eline = sline end
            if sline >= total then sline = total - 1 end
            if eline >= total then eline = total - 1 end

            local seg = {}
            for i = sline + 1, eline + 1 do seg[#seg + 1] = lines[i] end
            local txt = join(seg)
            local rr = C.LspRange(C.LspPos(sline, 0), C.LspPos(eline + 1, 0))
            return C.FormatResult(txt, rr, true)
        end

        local text = join(lines)
        return C.FormatResult(text, C.LspRange(C.LspPos(0, 0), C.LspPos(0, 0)), false)
    end)

    return {
        format_file_phase = format_file,
        format_file = format_file,
        C = C,
    }
end

return M
