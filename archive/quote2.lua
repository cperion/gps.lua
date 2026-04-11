-- quote2.lua — typed hygienic code builder for generated Lua/LuaJIT
--
-- Unlike quote.lua, quote2 builds a small structured IR:
--   names, labels, captures
--   expressions, lvalues, statements, blocks, chunks
--
-- The builder owns hygiene. Rendering is the only textual step.
--
-- Typical use:
--   local Q = require("quote2")
--   local q = Q()
--   local x = q:local_("x")
--   q:local_stmt({ x }, { 42 })
--   q:return_({ x })
--   local fn, src = q:compile("=demo")

local M = {}
local unpack = table.unpack or unpack

local NEXT_NAME_ID = 0
local NEXT_LABEL_ID = 0
local NEXT_CAPTURE_ID = 0

local function sanitize_hint(hint)
    hint = tostring(hint or "v"):gsub("[^_%w]", "_")
    if hint == "" then hint = "v" end
    if hint:match("^[0-9]") then hint = "_" .. hint end
    return hint
end

local function class(kind)
    local mt = { kind = kind }
    mt.__index = mt
    mt.__tostring = function(self)
        if self.hint ~= nil and self.id ~= nil then
            return string.format("%s(%s,%d)", kind, tostring(self.hint), self.id)
        end
        return kind
    end
    return mt
end

local Name_mt = class("Q2.Name")
local Label_mt = class("Q2.Label")
local Capture_mt = class("Q2.Capture")

local Ref_mt = class("Q2.Ref")
local Cap_mt = class("Q2.Cap")
local Nil_mt = class("Q2.Nil")
local Bool_mt = class("Q2.Bool")
local Num_mt = class("Q2.Num")
local Str_mt = class("Q2.Str")
local Call_mt = class("Q2.Call")
local Index_mt = class("Q2.Index")
local Field_mt = class("Q2.Field")
local BinOp_mt = class("Q2.BinOp")
local UnOp_mt = class("Q2.UnOp")
local Table_mt = class("Q2.Table")
local ArrayItem_mt = class("Q2.ArrayItem")
local FieldItem_mt = class("Q2.FieldItem")
local PairItem_mt = class("Q2.PairItem")
local Func_mt = class("Q2.Func")

local LRef_mt = class("Q2.LRef")
local LIndex_mt = class("Q2.LIndex")
local LField_mt = class("Q2.LField")

local Local_mt = class("Q2.Local")
local Assign_mt = class("Q2.Assign")
local If_mt = class("Q2.If")
local While_mt = class("Q2.While")
local ForNum_mt = class("Q2.ForNum")
local Do_mt = class("Q2.Do")
local ExprStmt_mt = class("Q2.ExprStmt")
local Return_mt = class("Q2.Return")
local LabelStmt_mt = class("Q2.LabelStmt")
local Goto_mt = class("Q2.Goto")
local Break_mt = class("Q2.Break")

local Block_mt = class("Q2.Block")
local Chunk_mt = class("Q2.Chunk")

local function Name(hint)
    NEXT_NAME_ID = NEXT_NAME_ID + 1
    return setmetatable({ hint = sanitize_hint(hint or "v"), id = NEXT_NAME_ID }, Name_mt)
end

local function Label(hint)
    NEXT_LABEL_ID = NEXT_LABEL_ID + 1
    return setmetatable({ hint = sanitize_hint(hint or "label"), id = NEXT_LABEL_ID }, Label_mt)
end

local function Capture(value, hint)
    NEXT_CAPTURE_ID = NEXT_CAPTURE_ID + 1
    return setmetatable({ value = value, hint = sanitize_hint(hint or "cap"), id = NEXT_CAPTURE_ID }, Capture_mt)
end

local function Ref(name) return setmetatable({ name = name }, Ref_mt) end
local function Cap(cap) return setmetatable({ cap = cap }, Cap_mt) end
local NIL = setmetatable({}, Nil_mt)
local function Bool(v) return setmetatable({ value = not not v }, Bool_mt) end
local function Num(v) return setmetatable({ value = v }, Num_mt) end
local function Str(v) return setmetatable({ value = v }, Str_mt) end
local function Call(fn, args) return setmetatable({ fn = fn, args = args }, Call_mt) end
local function Index(obj, key) return setmetatable({ obj = obj, key = key }, Index_mt) end
local function Field(obj, key) return setmetatable({ obj = obj, key = key }, Field_mt) end
local function BinOp(op, left, right) return setmetatable({ op = op, left = left, right = right }, BinOp_mt) end
local function UnOp(op, inner) return setmetatable({ op = op, inner = inner }, UnOp_mt) end
local function Table(items) return setmetatable({ items = items }, Table_mt) end
local function ArrayItem(value) return setmetatable({ value = value }, ArrayItem_mt) end
local function FieldItem(key, value) return setmetatable({ key = key, value = value }, FieldItem_mt) end
local function PairItem(key, value) return setmetatable({ key = key, value = value }, PairItem_mt) end
local function Func(params, body) return setmetatable({ params = params, body = body }, Func_mt) end

local function LRef(name) return setmetatable({ name = name }, LRef_mt) end
local function LIndex(obj, key) return setmetatable({ obj = obj, key = key }, LIndex_mt) end
local function LField(obj, key) return setmetatable({ obj = obj, key = key }, LField_mt) end

local function Local(names, inits) return setmetatable({ names = names, inits = inits }, Local_mt) end
local function Assign(lhs, rhs) return setmetatable({ lhs = lhs, rhs = rhs }, Assign_mt) end
local function If(cond, yes, no) return setmetatable({ cond = cond, yes = yes, no = no }, If_mt) end
local function While(cond, body) return setmetatable({ cond = cond, body = body }, While_mt) end
local function ForNum(var, lo, hi, step, body) return setmetatable({ var = var, lo = lo, hi = hi, step = step, body = body }, ForNum_mt) end
local function Do(body) return setmetatable({ body = body }, Do_mt) end
local function ExprStmt(expr) return setmetatable({ expr = expr }, ExprStmt_mt) end
local function Return(values) return setmetatable({ values = values }, Return_mt) end
local function LabelStmt(label) return setmetatable({ label = label }, LabelStmt_mt) end
local function Goto(label) return setmetatable({ label = label }, Goto_mt) end
local BREAK = setmetatable({}, Break_mt)

local function Block(stmts) return setmetatable({ stmts = stmts or {} }, Block_mt) end
local function Chunk(captures, body) return setmetatable({ captures = captures, body = body }, Chunk_mt) end

local expr_mts = {
    [Ref_mt] = true, [Cap_mt] = true, [Nil_mt] = true, [Bool_mt] = true, [Num_mt] = true,
    [Str_mt] = true, [Call_mt] = true, [Index_mt] = true, [Field_mt] = true,
    [BinOp_mt] = true, [UnOp_mt] = true, [Table_mt] = true, [Func_mt] = true,
}
local lvalue_mts = { [LRef_mt] = true, [LIndex_mt] = true, [LField_mt] = true }
local stmt_mts = {
    [Local_mt] = true, [Assign_mt] = true, [If_mt] = true, [While_mt] = true,
    [ForNum_mt] = true, [Do_mt] = true, [ExprStmt_mt] = true, [Return_mt] = true,
    [LabelStmt_mt] = true, [Goto_mt] = true, [Break_mt] = true,
}

local function is_name(x) return getmetatable(x) == Name_mt end
local function is_label(x) return getmetatable(x) == Label_mt end
local function is_capture(x) return getmetatable(x) == Capture_mt end
local function is_expr(x) return expr_mts[getmetatable(x)] or false end
local function is_lvalue(x) return lvalue_mts[getmetatable(x)] or false end
local function is_stmt(x) return stmt_mts[getmetatable(x)] or false end
local function is_block(x) return getmetatable(x) == Block_mt end
local function is_chunk(x) return getmetatable(x) == Chunk_mt end

local function list_copy(xs)
    local out = {}
    for i = 1, #xs do out[i] = xs[i] end
    return out
end

local Builder = {}
Builder.__index = Builder

local function make_builder(state, block)
    return setmetatable({ _state = state, _block = block }, Builder)
end

local function as_expr(self, x)
    if x == nil then return NIL end
    if is_expr(x) then return x end
    if is_name(x) then return Ref(x) end
    if is_capture(x) then return Cap(x) end
    local tp = type(x)
    if tp == "boolean" then return Bool(x) end
    if tp == "number" then return Num(x) end
    if tp == "string" then return Str(x) end
    error("quote2: cannot coerce to expression from " .. tp, 3)
end

local function as_lvalue(self, x)
    if is_lvalue(x) then return x end
    if is_name(x) then return LRef(x) end
    error("quote2: cannot coerce to lvalue", 3)
end

local function ensure_name(x)
    if not is_name(x) then error("quote2: expected Name", 3) end
    return x
end

local function ensure_label(x)
    if not is_label(x) then error("quote2: expected Label", 3) end
    return x
end

local function as_name_list(xs)
    local out = {}
    for i = 1, #xs do out[i] = ensure_name(xs[i]) end
    return out
end

function M.new()
    local state = { captures = {} }
    return make_builder(state, Block())
end

function Builder:local_(hint)
    return Name(hint)
end

function Builder:label(hint)
    return Label(hint)
end

function Builder:capture(value, hint)
    local cap = Capture(value, hint)
    self._state.captures[#self._state.captures + 1] = cap
    return cap
end

function Builder:ref(name) return Ref(ensure_name(name)) end
function Builder:cap(cap) return Cap(cap) end
function Builder:nil_() return NIL end
function Builder:bool(v) return Bool(v) end
function Builder:num(v) return Num(v) end
function Builder:str(v) return Str(v) end
function Builder:call(fn, args)
    local out = {}
    args = args or {}
    for i = 1, #args do out[i] = as_expr(self, args[i]) end
    return Call(as_expr(self, fn), out)
end
function Builder:index(obj, key) return Index(as_expr(self, obj), as_expr(self, key)) end
function Builder:field(obj, key) return Field(as_expr(self, obj), key) end
function Builder:bin(op, left, right) return BinOp(op, as_expr(self, left), as_expr(self, right)) end
function Builder:un(op, inner) return UnOp(op, as_expr(self, inner)) end
function Builder:item(value) return ArrayItem(as_expr(self, value)) end
function Builder:field_item(key, value) return FieldItem(key, as_expr(self, value)) end
function Builder:pair_item(key, value) return PairItem(as_expr(self, key), as_expr(self, value)) end
function Builder:table(items)
    local out = {}
    items = items or {}
    for i = 1, #items do
        local item = items[i]
        local mt = getmetatable(item)
        if mt == ArrayItem_mt or mt == FieldItem_mt or mt == PairItem_mt then
            out[i] = item
        else
            out[i] = ArrayItem(as_expr(self, item))
        end
    end
    return Table(out)
end

function Builder:lref(name) return LRef(ensure_name(name)) end
function Builder:lindex(obj, key) return LIndex(as_expr(self, obj), as_expr(self, key)) end
function Builder:lfield(obj, key) return LField(as_expr(self, obj), key) end

function Builder:func(params, fn)
    params = as_name_list(params or {})
    local body = Block()
    local b = make_builder(self._state, body)
    if fn then fn(b, params) end
    return Func(params, body)
end

function Builder:stmt(stmt)
    if not is_stmt(stmt) then error("quote2: expected statement", 2) end
    self._block.stmts[#self._block.stmts + 1] = stmt
    return stmt
end

function Builder:local_stmt(names, inits)
    local out = {}
    inits = inits or {}
    for i = 1, #inits do out[i] = as_expr(self, inits[i]) end
    return self:stmt(Local(as_name_list(names or {}), out))
end

function Builder:assign(lhs, rhs)
    local ls, rs = {}, {}
    lhs = lhs or {}
    rhs = rhs or {}
    for i = 1, #lhs do ls[i] = as_lvalue(self, lhs[i]) end
    for i = 1, #rhs do rs[i] = as_expr(self, rhs[i]) end
    return self:stmt(Assign(ls, rs))
end

function Builder:expr_stmt(expr)
    return self:stmt(ExprStmt(as_expr(self, expr)))
end

function Builder:return_(values)
    local out = {}
    values = values or {}
    for i = 1, #values do out[i] = as_expr(self, values[i]) end
    return self:stmt(Return(out))
end

function Builder:if_(cond, yes_fn, no_fn)
    local yes = Block()
    local yb = make_builder(self._state, yes)
    if yes_fn then yes_fn(yb) end
    local no = nil
    if no_fn then
        no = Block()
        local nb = make_builder(self._state, no)
        no_fn(nb)
    end
    return self:stmt(If(as_expr(self, cond), yes, no))
end

function Builder:while_(cond, body_fn)
    local body = Block()
    local bb = make_builder(self._state, body)
    if body_fn then body_fn(bb) end
    return self:stmt(While(as_expr(self, cond), body))
end

function Builder:for_num(var, lo, hi, step, body_fn)
    local body = Block()
    local bb = make_builder(self._state, body)
    if body_fn then body_fn(bb, var) end
    return self:stmt(ForNum(ensure_name(var), as_expr(self, lo), as_expr(self, hi), as_expr(self, step), body))
end

function Builder:do_(body_fn)
    local body = Block()
    local bb = make_builder(self._state, body)
    if body_fn then body_fn(bb) end
    return self:stmt(Do(body))
end

function Builder:goto_(label)
    return self:stmt(Goto(ensure_label(label)))
end

function Builder:label_stmt(label)
    return self:stmt(LabelStmt(ensure_label(label)))
end

function Builder:break_()
    return self:stmt(BREAK)
end

function Builder:emit(other)
    local chunk = other:chunk()
    local existing = {}
    for i = 1, #self._state.captures do existing[self._state.captures[i]] = true end
    for i = 1, #chunk.captures do
        local cap = chunk.captures[i]
        if not existing[cap] then
            existing[cap] = true
            self._state.captures[#self._state.captures + 1] = cap
        end
    end
    for i = 1, #chunk.body.stmts do
        self._block.stmts[#self._block.stmts + 1] = chunk.body.stmts[i]
    end
    return self
end

function Builder:block()
    return self._block
end

function Builder:chunk()
    return Chunk(list_copy(self._state.captures), self._block)
end

local function validate_expr(expr)
    local mt = getmetatable(expr)
    if mt == Ref_mt then ensure_name(expr.name)
    elseif mt == Cap_mt then assert(is_capture(expr.cap), "quote2: invalid capture ref")
    elseif mt == Nil_mt or mt == Bool_mt or mt == Num_mt or mt == Str_mt then
        return true
    elseif mt == Call_mt then
        validate_expr(expr.fn)
        for i = 1, #expr.args do validate_expr(expr.args[i]) end
    elseif mt == Index_mt then
        validate_expr(expr.obj); validate_expr(expr.key)
    elseif mt == Field_mt then
        validate_expr(expr.obj)
    elseif mt == BinOp_mt then
        validate_expr(expr.left); validate_expr(expr.right)
    elseif mt == UnOp_mt then
        validate_expr(expr.inner)
    elseif mt == Table_mt then
        for i = 1, #expr.items do
            local item = expr.items[i]
            local imt = getmetatable(item)
            if imt == ArrayItem_mt then validate_expr(item.value)
            elseif imt == FieldItem_mt then validate_expr(item.value)
            elseif imt == PairItem_mt then validate_expr(item.key); validate_expr(item.value)
            else error("quote2: invalid table item", 3) end
        end
    elseif mt == Func_mt then
        for i = 1, #expr.params do ensure_name(expr.params[i]) end
        local labels = {}
        local gotos = {}
        local function validate_stmt(stmt)
            local smt = getmetatable(stmt)
            if smt == Local_mt then
                for i = 1, #stmt.names do ensure_name(stmt.names[i]) end
                for i = 1, #stmt.inits do validate_expr(stmt.inits[i]) end
            elseif smt == Assign_mt then
                for i = 1, #stmt.lhs do
                    local lmt = getmetatable(stmt.lhs[i])
                    if lmt == LRef_mt then ensure_name(stmt.lhs[i].name)
                    elseif lmt == LIndex_mt then validate_expr(stmt.lhs[i].obj); validate_expr(stmt.lhs[i].key)
                    elseif lmt == LField_mt then validate_expr(stmt.lhs[i].obj)
                    else error("quote2: invalid lvalue", 3) end
                end
                for i = 1, #stmt.rhs do validate_expr(stmt.rhs[i]) end
            elseif smt == If_mt then
                validate_expr(stmt.cond)
                for i = 1, #stmt.yes.stmts do validate_stmt(stmt.yes.stmts[i]) end
                if stmt.no then for i = 1, #stmt.no.stmts do validate_stmt(stmt.no.stmts[i]) end end
            elseif smt == While_mt then
                validate_expr(stmt.cond)
                for i = 1, #stmt.body.stmts do validate_stmt(stmt.body.stmts[i]) end
            elseif smt == ForNum_mt then
                ensure_name(stmt.var)
                validate_expr(stmt.lo); validate_expr(stmt.hi); validate_expr(stmt.step)
                for i = 1, #stmt.body.stmts do validate_stmt(stmt.body.stmts[i]) end
            elseif smt == Do_mt then
                for i = 1, #stmt.body.stmts do validate_stmt(stmt.body.stmts[i]) end
            elseif smt == ExprStmt_mt then
                validate_expr(stmt.expr)
            elseif smt == Return_mt then
                for i = 1, #stmt.values do validate_expr(stmt.values[i]) end
            elseif smt == LabelStmt_mt then
                ensure_label(stmt.label)
                labels[stmt.label] = true
            elseif smt == Goto_mt then
                ensure_label(stmt.label)
                gotos[#gotos + 1] = stmt.label
            elseif smt == Break_mt then
                return true
            else
                error("quote2: invalid statement", 3)
            end
        end
        for i = 1, #expr.body.stmts do validate_stmt(expr.body.stmts[i]) end
        for i = 1, #gotos do
            if not labels[gotos[i]] then error("quote2: goto to undefined label", 3) end
        end
    else
        error("quote2: invalid expression", 3)
    end
    return true
end

function M.validate(chunk)
    if not is_chunk(chunk) then error("quote2.validate: expected Chunk", 2) end
    local root = Func({}, chunk.body)
    validate_expr(root)
    return true
end

local function render_name(name)
    return string.format("_q2n%d_%s", name.id, name.hint)
end

local function render_label(label)
    return string.format("_q2l%d_%s", label.id, label.hint)
end

local function render_capture(cap)
    return string.format("_q2c%d_%s", cap.id, cap.hint)
end

local ident_pat = "^[_%a][_%w]*$"
local function is_ident(s) return type(s) == "string" and s:match(ident_pat) ~= nil end

local render_block
local render_lvalue
local render_stmt

local function render_expr(expr, indent)
    local mt = getmetatable(expr)
    if mt == Ref_mt then return render_name(expr.name)
    elseif mt == Cap_mt then return render_capture(expr.cap)
    elseif mt == Nil_mt then return "nil"
    elseif mt == Bool_mt then return expr.value and "true" or "false"
    elseif mt == Num_mt then return tostring(expr.value)
    elseif mt == Str_mt then return string.format("%q", expr.value)
    elseif mt == Call_mt then
        local args = {}
        for i = 1, #expr.args do args[i] = render_expr(expr.args[i], indent) end
        return string.format("%s(%s)", render_expr(expr.fn, indent), table.concat(args, ", "))
    elseif mt == Index_mt then
        return string.format("%s[%s]", render_expr(expr.obj, indent), render_expr(expr.key, indent))
    elseif mt == Field_mt then
        if is_ident(expr.key) then
            return string.format("%s.%s", render_expr(expr.obj, indent), expr.key)
        end
        return string.format("%s[%q]", render_expr(expr.obj, indent), expr.key)
    elseif mt == BinOp_mt then
        return string.format("(%s %s %s)", render_expr(expr.left, indent), expr.op, render_expr(expr.right, indent))
    elseif mt == UnOp_mt then
        return string.format("(%s %s)", expr.op, render_expr(expr.inner, indent))
    elseif mt == Table_mt then
        local items = {}
        for i = 1, #expr.items do
            local item = expr.items[i]
            local imt = getmetatable(item)
            if imt == ArrayItem_mt then
                items[i] = render_expr(item.value, indent)
            elseif imt == FieldItem_mt then
                if is_ident(item.key) then
                    items[i] = string.format("%s = %s", item.key, render_expr(item.value, indent))
                else
                    items[i] = string.format("[%q] = %s", item.key, render_expr(item.value, indent))
                end
            else
                items[i] = string.format("[%s] = %s", render_expr(item.key, indent), render_expr(item.value, indent))
            end
        end
        return "{ " .. table.concat(items, ", ") .. " }"
    elseif mt == Func_mt then
        local lines = {}
        local params = {}
        for i = 1, #expr.params do params[i] = render_name(expr.params[i]) end
        lines[#lines + 1] = string.format("function(%s)", table.concat(params, ", "))
        local body = render_block(expr.body, (indent or 0) + 1)
        if body ~= "" then lines[#lines + 1] = body end
        lines[#lines + 1] = string.rep("  ", indent or 0) .. "end"
        return table.concat(lines, "\n")
    end
    error("quote2: cannot render expression kind " .. tostring(mt and mt.kind), 2)
end

render_lvalue = function(lv, indent)
    local mt = getmetatable(lv)
    if mt == LRef_mt then return render_name(lv.name) end
    if mt == LIndex_mt then return string.format("%s[%s]", render_expr(lv.obj, indent), render_expr(lv.key, indent)) end
    if mt == LField_mt then
        if is_ident(lv.key) then return string.format("%s.%s", render_expr(lv.obj, indent), lv.key) end
        return string.format("%s[%q]", render_expr(lv.obj, indent), lv.key)
    end
    error("quote2: cannot render lvalue", 2)
end

render_stmt = function(stmt, indent)
    local pad = string.rep("  ", indent or 0)
    local mt = getmetatable(stmt)
    if mt == Local_mt then
        local names, inits = {}, {}
        for i = 1, #stmt.names do names[i] = render_name(stmt.names[i]) end
        for i = 1, #stmt.inits do inits[i] = render_expr(stmt.inits[i], indent) end
        if #inits > 0 then
            return string.format("%slocal %s = %s", pad, table.concat(names, ", "), table.concat(inits, ", "))
        end
        return string.format("%slocal %s", pad, table.concat(names, ", "))
    elseif mt == Assign_mt then
        local lhs, rhs = {}, {}
        for i = 1, #stmt.lhs do lhs[i] = render_lvalue(stmt.lhs[i], indent) end
        for i = 1, #stmt.rhs do rhs[i] = render_expr(stmt.rhs[i], indent) end
        return string.format("%s%s = %s", pad, table.concat(lhs, ", "), table.concat(rhs, ", "))
    elseif mt == If_mt then
        local lines = { string.format("%sif %s then", pad, render_expr(stmt.cond, indent)) }
        local yes = render_block(stmt.yes, (indent or 0) + 1)
        if yes ~= "" then lines[#lines + 1] = yes end
        if stmt.no and #stmt.no.stmts > 0 then
            lines[#lines + 1] = pad .. "else"
            local no = render_block(stmt.no, (indent or 0) + 1)
            if no ~= "" then lines[#lines + 1] = no end
        end
        lines[#lines + 1] = pad .. "end"
        return table.concat(lines, "\n")
    elseif mt == While_mt then
        local lines = { string.format("%swhile %s do", pad, render_expr(stmt.cond, indent)) }
        local body = render_block(stmt.body, (indent or 0) + 1)
        if body ~= "" then lines[#lines + 1] = body end
        lines[#lines + 1] = pad .. "end"
        return table.concat(lines, "\n")
    elseif mt == ForNum_mt then
        local lines = { string.format("%sfor %s = %s, %s, %s do", pad, render_name(stmt.var), render_expr(stmt.lo, indent), render_expr(stmt.hi, indent), render_expr(stmt.step, indent)) }
        local body = render_block(stmt.body, (indent or 0) + 1)
        if body ~= "" then lines[#lines + 1] = body end
        lines[#lines + 1] = pad .. "end"
        return table.concat(lines, "\n")
    elseif mt == Do_mt then
        local lines = { pad .. "do" }
        local body = render_block(stmt.body, (indent or 0) + 1)
        if body ~= "" then lines[#lines + 1] = body end
        lines[#lines + 1] = pad .. "end"
        return table.concat(lines, "\n")
    elseif mt == ExprStmt_mt then
        return pad .. render_expr(stmt.expr, indent)
    elseif mt == Return_mt then
        local values = {}
        for i = 1, #stmt.values do values[i] = render_expr(stmt.values[i], indent) end
        return pad .. "return " .. table.concat(values, ", ")
    elseif mt == LabelStmt_mt then
        return pad .. "::" .. render_label(stmt.label) .. "::"
    elseif mt == Goto_mt then
        return pad .. "goto " .. render_label(stmt.label)
    elseif mt == Break_mt then
        return pad .. "break"
    end
    error("quote2: cannot render statement kind " .. tostring(mt and mt.kind), 2)
end

render_block = function(block, indent)
    local lines = {}
    for i = 1, #block.stmts do
        lines[#lines + 1] = render_stmt(block.stmts[i], indent)
    end
    return table.concat(lines, "\n")
end

function M.render(chunk)
    if not is_chunk(chunk) then error("quote2.render: expected Chunk", 2) end
    M.validate(chunk)
    local lines = {}
    if #chunk.captures > 0 then
        local names = {}
        for i = 1, #chunk.captures do names[i] = render_capture(chunk.captures[i]) end
        lines[#lines + 1] = "local " .. table.concat(names, ", ") .. " = ..."
    end
    local body = render_block(chunk.body, 0)
    if body ~= "" then lines[#lines + 1] = body end
    return table.concat(lines, "\n")
end

function M.compile_source(src, captures, name)
    local cvals = {}
    for i = 1, #captures do cvals[i] = captures[i].value end
    local fn, err
    if loadstring then
        fn, err = loadstring(src, name or "=(quote2)")
        if not fn then error(err .. "\n--- generated source ---\n" .. src, 2) end
    else
        fn, err = load(src, name or "=(quote2)", "t")
        if not fn then error(err .. "\n--- generated source ---\n" .. src, 2) end
    end
    return fn(unpack(cvals)), src
end

function Builder:source(_name)
    return M.render(self:chunk())
end

function Builder:compile(name)
    local chunk = self:chunk()
    local src = M.render(chunk)
    return M.compile_source(src, chunk.captures, name)
end

M.Name = Name
M.Label = Label
M.Capture = Capture
M.Block = Block
M.Chunk = Chunk
M.types = {
    Name = Name_mt, Label = Label_mt, Capture = Capture_mt,
    Ref = Ref_mt, Cap = Cap_mt, Nil = Nil_mt, Bool = Bool_mt, Num = Num_mt, Str = Str_mt,
    Call = Call_mt, Index = Index_mt, Field = Field_mt, BinOp = BinOp_mt, UnOp = UnOp_mt,
    Table = Table_mt, ArrayItem = ArrayItem_mt, FieldItem = FieldItem_mt, PairItem = PairItem_mt, Func = Func_mt,
    LRef = LRef_mt, LIndex = LIndex_mt, LField = LField_mt,
    Local = Local_mt, Assign = Assign_mt, If = If_mt, While = While_mt, ForNum = ForNum_mt,
    Do = Do_mt, ExprStmt = ExprStmt_mt, Return = Return_mt, LabelStmt = LabelStmt_mt, Goto = Goto_mt, Break = Break_mt,
    Block = Block_mt, Chunk = Chunk_mt,
}

setmetatable(M, { __call = function() return M.new() end })
return M
